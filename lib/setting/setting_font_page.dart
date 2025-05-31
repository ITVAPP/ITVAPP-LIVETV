import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// SelectionState 类用于管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 当前聚焦的按钮索引
  final int selectedIndex; // 当前选中的选项索引

  SelectionState(this.focusedIndex, this.selectedIndex);

  // 优化：添加相等性比较，避免无效状态更新
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

// 字体设置页面主类，管理字体和语言设置
class SettingFontPage extends StatefulWidget {
  const SettingFontPage({super.key});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

// 字体设置页面的状态类，处理逻辑和界面更新
class _SettingFontPageState extends State<SettingFontPage> {
  // 定义静态常量样式，提升复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 页面标题样式
  static const _sectionTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold); // 章节标题样式
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 6); // 按钮内边距
  static const _maxContainerWidth = 580.0; // 容器最大宽度
  static const _sectionPadding = EdgeInsets.all(15.0); // 章节内边距

  final _fontScales = [0.8, 0.9, 1.0, 1.1, 1.2]; // 可选字体缩放比例列表
  final _languages = ['English', '简体中文', '正體中文']; // 可选语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 对应的语言代码

  // 统一按钮圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 设置圆角半径
  );

  // 定义按钮颜色
  final _selectedColor = const Color(0xFFEB144C); // 选中时的背景色（红色）
  final _unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景色（黄色）

  // 焦点节点列表，管理字体和语言按钮的焦点
  late final List<FocusNode> _focusNodes;

  // 分组焦点缓存，用于TV导航优化
  late final Map<int, Map<String, FocusNode>> _groupFocusCache;

  // 管理字体和语言的选择状态
  late SelectionState _fontState; // 字体缩放状态
  late SelectionState _langState; // 语言选择状态

  @override
  void initState() {
    super.initState();

    // 初始化焦点节点总数：字体 + 语言
    final totalNodes = _fontScales.length + _languages.length;
    _focusNodes = List<FocusNode>.generate(totalNodes, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 添加焦点变化监听
      return node;
    });

    // 初始化分组焦点缓存
    _groupFocusCache = _generateGroupFocusCache();

    // 初始化状态：默认选中字体 1.0 和 English
    _fontState = SelectionState(-1, _fontScales.indexOf(1.0)); // 默认选中字体缩放 1.0
    _langState = SelectionState(-1, 0); // 默认选中 English
  }

  // 生成分组焦点缓存，优化TV导航
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache() {
    final cache = <int, Map<String, FocusNode>>{};

    // 分组 0：字体大小按钮
    cache[0] = {
      'firstFocusNode': _focusNodes[0], // 字体组首个焦点
      'lastFocusNode': _focusNodes[_fontScales.length - 1], // 字体组末尾焦点
    };

    // 分组 1 及以上：语言选择按钮
    for (int i = 0; i < _languages.length; i++) {
      final nodeIndex = _fontScales.length + i;
      cache[i + 1] = {
        'firstFocusNode': _focusNodes[nodeIndex], // 语言按钮焦点
        'lastFocusNode': _focusNodes[nodeIndex], // 每个语言单节点
      };
    }

    return cache;
  }

  // 优化：处理焦点变化，添加状态比较减少无效更新
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      SelectionState newFontState = _fontState;
      SelectionState newLangState = _langState;
      
      if (focusedIndex < _fontScales.length) {
        newFontState = SelectionState(focusedIndex, _fontState.selectedIndex); // 更新字体焦点
      } else {
        newLangState = SelectionState(focusedIndex - _fontScales.length, _langState.selectedIndex); // 更新语言焦点
      }
      
      // 优化：只有状态实际发生变化时才执行setState
      if (newFontState != _fontState || newLangState != _langState) {
        if (mounted) {
          setState(() {
            _fontState = newFontState;
            _langState = newLangState;
          });
        }
      }
    } else {
      // 未找到焦点时延迟检查
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          SelectionState newFontState = _fontState;
          SelectionState newLangState = _langState;
          
          if (newFocusedIndex < _fontScales.length) {
            newFontState = SelectionState(newFocusedIndex, _fontState.selectedIndex);
          } else {
            newLangState = SelectionState(newFocusedIndex - _fontScales.length, _langState.selectedIndex);
          }
          
          // 优化：延迟回调中也添加状态比较
          if (newFontState != _fontState || newLangState != _langState) {
            setState(() {
              _fontState = newFontState;
              _langState = newLangState;
            });
          }
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

  // 计算按钮颜色，动态调整焦点和选中状态
  Color _getChipColor(bool isFocused, bool isSelected) {
    if (isFocused) {
      return isSelected ? darkenColor(_selectedColor) : darkenColor(_unselectedColor);
    }
    return isSelected ? _selectedColor : _unselectedColor;
  }

  // 构建通用 ChoiceChip 组件
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
      onSelected: (bool selected) => onSelected(), // 点击触发回调
      selectedColor: _getChipColor(isFocused, true),
      backgroundColor: _getChipColor(isFocused, false),
      shape: _buttonShape, // 应用统一圆角样式
      padding: _buttonPadding, // 应用统一内边距
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width; // 获取屏幕宽度
    
    return Scaffold(
      // 优化：使用Selector精确监听isTV属性，减少不必要的重建
      backgroundColor: Selector<ThemeProvider, bool>(
        selector: (context, themeProvider) => themeProvider.isTV,
        builder: (context, isTV, child) => isTV ? const Color(0xFF1E2022) : Colors.transparent,
      ).color,
      appBar: AppBar(
        // 优化：使用Selector精确监听isTV属性
        leading: Selector<ThemeProvider, bool>(
          selector: (context, themeProvider) => themeProvider.isTV,
          builder: (context, isTV, child) => isTV ? const SizedBox.shrink() : const BackButton(),
        ),
        title: Text(
          S.of(context).fontTitle, // 显示"字体设置"标题
          style: _titleStyle,
        ),
        // 优化：使用Selector精确监听isTV属性
        backgroundColor: Selector<ThemeProvider, Color?>(
          selector: (context, themeProvider) => themeProvider.isTV ? const Color(0xFF1E2022) : null,
          builder: (context, backgroundColor, child) => backgroundColor,
        ).value,
      ),
      body: FocusScope(
        child: Selector<ThemeProvider, bool>(
          selector: (context, themeProvider) => themeProvider.isTV,
          builder: (context, isTV, child) => TvKeyNavigation(
            focusNodes: _focusNodes, // 绑定焦点节点
            groupFocusCache: _groupFocusCache, // 绑定分组焦点缓存
            isHorizontalGroup: true, // 启用横向分组导航
            initialIndex: 0, // 初始焦点索引
            isFrame: isTV ? true : false, // TV模式启用框架导航
            frameType: isTV ? "child" : null, // TV模式标记为子页面
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
      ),
    );
  }
}

// 无状态组件：字体大小选择部分
class FontSizeSection extends StatelessWidget {
  final List<FocusNode> focusNodes; // 字体按钮焦点节点
  final List<double> fontScales; // 字体缩放比例列表
  final SelectionState state; // 当前字体状态
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
          S.of(context).fontSizeTitle, // 显示"字体大小"标题
          style: _SettingFontPageState._sectionTitleStyle,
        ),
        const SizedBox(height: 10), // 标题与按钮间距
        Group(
          groupIndex: 0, // 字体大小分组
          children: [
            Wrap(
              spacing: 5, // 按钮水平间距
              runSpacing: 8, // 按钮垂直间距
              children: List.generate(
                fontScales.length,
                (index) => FocusableItem(
                  focusNode: focusNodes[index], // 绑定焦点节点
                  child: buildChoiceChip(
                    focusNode: focusNodes[index],
                    labelText: '${fontScales[index]}', // 显示缩放比例
                    isSelected: state.selectedIndex == index,
                    // 优化：使用Selector精确监听setTextScale方法
                    onSelected: () => context.read<ThemeProvider>().setTextScale(fontScales[index]), // 设置字体缩放
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
  final List<FocusNode> focusNodes; // 语言按钮焦点节点
  final List<String> languages; // 语言名称列表
  final List<String> languageCodes; // 语言代码列表
  final SelectionState state; // 当前语言状态
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
    // 优化：使用Selector精确监听currentLocale属性
    return Selector<LanguageProvider, String>(
      selector: (context, languageProvider) => languageProvider.currentLocale.toString(),
      builder: (context, currentLocale, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.of(context).languageSelection, // 显示"语言选择"标题
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
                    groupIndex: index + 1, // 语言分组索引
                    children: [
                      FocusableItem(
                        focusNode: focusNodes[index], // 绑定焦点节点
                        child: buildChoiceChip(
                          focusNode: focusNodes[index],
                          labelText: currentLocale == languageCodes[index]
                              ? S.of(context).inUse // 当前使用中
                              : S.of(context).use, // 使用此语言
                          isSelected: state.selectedIndex == index,
                          onSelected: () async {
                            // 记录当前语言代码，用于后续比较
                            final currentLanguageCode = currentLocale;
                            
                            // 切换语言
                            await context.read<LanguageProvider>().changeLanguage(languageCodes[index]);
                            
                            // 更新语言选中状态
                            final parentState = context.findAncestorStateOfType<_SettingFontPageState>();
                            if (parentState != null && parentState.mounted) {
                              final newLangState = SelectionState(state.focusedIndex, index);
                              // 优化：只有状态实际发生变化时才执行setState
                              if (newLangState != parentState._langState) {
                                parentState.setState(() {
                                  parentState._langState = newLangState; // 更新语言选中状态
                                });
                              }
                            }
                            
                            // 检查是否为中文语言间的切换
                            final newLanguageCode = languageCodes[index];
                            final isChinese = _isChinese(newLanguageCode);
                            final wasChineseBefore = _isChinese(currentLanguageCode);
                            final isChineseVariantChange = 
                                (currentLanguageCode.contains("CN") && newLanguageCode.contains("TW")) ||
                                (currentLanguageCode.contains("TW") && newLanguageCode.contains("CN"));
                            
                            // 如果切换到中文或在不同中文变体间切换，显示提示信息
                            if (isChinese && ((!wasChineseBefore) || isChineseVariantChange)) {
                              CustomSnackBar.showSnackBar(
                                context, 
                                S.of(context).langTip,
                                duration: const Duration(seconds: 5),
                              );
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
      ),
    );
  }
  
  // 辅助方法：检查语言代码是否为中文
  bool _isChinese(String languageCode) {
    return languageCode == 'zh' || languageCode.startsWith('zh_');
  }
}
