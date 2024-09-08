import 'package:itvapp_live_tv/provider/theme_provider.dart'; 
import 'package:itvapp_live_tv/provider/language_provider.dart'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingFontPage extends StatefulWidget {
  final bool isTV; // 是否为TV模式
  const SettingFontPage({super.key, this.isTV = false});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

class _SettingFontPageState extends State<SettingFontPage> {
  final _fontScales = [1.0, 1.1, 1.2, 1.3, 1.5]; // 字体缩放比例
  final _languages = ['English', '简体中文', '繁體中文']; // 语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 语言代码

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度以进行布局优化
    var screenWidth = MediaQuery.of(context).size.width;

    // 最大内容宽度，适用于大屏设备
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: widget.isTV ? const Color(0xFF1E2022) : null, // TV模式下的背景颜色
      appBar: AppBar(
        leading: widget.isTV ? const SizedBox.shrink() : null, // TV模式下不显示返回按钮
        title: const Text('设置'), // 设置页面标题
        backgroundColor: widget.isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: Align(
        alignment: Alignment.center, // 内容居中显示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // 子组件从左对齐
            children: [
              // 字体大小设置部分
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('字体大小', style: TextStyle(fontSize: 17)), // 字体大小标题
                    const SizedBox(height: 10), // 间距
                    Wrap(
                      spacing: 10,
                      runSpacing: 10, // 选项排列方式
                      children: List.generate(
                        _fontScales.length,
                        (index) => ChoiceChip(
                          label: Text(
                            '${_fontScales[index]}', // 显示字体缩放比例
                            style: const TextStyle(fontSize: 15),
                          ),
                          selected: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index], // 当前选中的字体缩放
                          onSelected: (bool selected) {
                            context.read<ThemeProvider>().setTextScale(_fontScales[index]); // 设置字体缩放
                          },
                          selectedColor: const Color(0xFFEB144C), // 选中状态颜色
                          backgroundColor: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                              ? const Color(0xFFEB144C) // 选中状态颜色
                              : Colors.grey[300], // 未选中状态颜色
                          shape: const StadiumBorder(), // 圆角外形
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20), // 间距

              // 语言选择部分
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('语言选择', style: TextStyle(fontSize: 17)), // 语言选择标题
                    const SizedBox(height: 10), // 间距
                    Column(
                      children: List.generate(
                        _languages.length,
                        (index) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左侧显示语言，右侧显示按钮
                          children: [
                            Text(_languages[index], style: const TextStyle(fontSize: 15)), // 显示语言名称
                            ChoiceChip(
                              label: Text(
                                context.watch<LanguageProvider>().currentLocale.languageCode == _languageCodes[index]
                                    ? '使用中' // 已选中的显示 "使用中"
                                    : '使用', // 未选中的显示 "使用"
                                style: const TextStyle(fontSize: 15),
                              ),
                              selected: context.watch<LanguageProvider>().currentLocale.languageCode == _languageCodes[index], // 当前选中的语言
                              onSelected: (bool selected) {
                                if (!selected) {
                                  context.read<LanguageProvider>().changeLanguage(_languageCodes[index]); // 切换语言
                                }
                              },
                              selectedColor: const Color(0xFFEB144C), // 选中状态颜色
                              backgroundColor: context.watch<LanguageProvider>().currentLocale.languageCode == _languageCodes[index]
                                  ? const Color(0xFFEB144C) // 已选中状态颜色
                                  : Colors.grey[300], // 未选中状态的颜色
                            ),
                          ],
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
    );
  }
}
