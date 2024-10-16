import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:itvapp_live_tv/setting/setting_beautify_page.dart';
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.2]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

// 电视设置主页面
class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key});

  @override
  State<TvSettingPage> createState() => _TvSettingPageState();
}

class _TvSettingPageState extends State<TvSettingPage> {
  int _selectedIndex = 1; // 当前选中的菜单索引，初始值为1
  int _confirmedIndex = 1; // 用户确认选择后显示的页面索引
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 存储最新版本信息

  final List<FocusNode> _focusNodes = _generateFocusNodes(6); // 创建焦点节点列表，长度为6，返回按钮用0，菜单用1开始

  final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色

  static List<FocusNode> _generateFocusNodes(int count) {
    return List.generate(count, (_) => FocusNode());
  }

  @override
  void dispose() {
    _disposeFocusNodes(_focusNodes); // 使用统一的焦点销毁方法
    super.dispose();
  }

  void _disposeFocusNodes(List<FocusNode> focusNodes) {
    for (var focusNode in focusNodes) {
      focusNode.dispose();
    }
  }

  // 用于检查版本更新的逻辑
  Future<void> _checkForUpdates() async {
    try {
      await CheckVersionUtil.checkVersion(context, true, true, true);
      setState(() {
        _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
      });

      // 如果有最新版本
      if (_latestVersionEntity != null) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).newVersion(_latestVersionEntity!.latestVersion!),
          duration: Duration(seconds: 4),
        );
      } else {
        // 没有最新版本
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).latestVersion,
          duration: Duration(seconds: 4),
        );
      }
    } catch (e) {
      LogUtil.e('Error checking for updates: $e'); // 添加日志记录
      // 版本检查失败
      CustomSnackBar.showSnackBar(
        context,
        S.of(context).netReceiveTimeout,
        duration: Duration(seconds: 4),
      );
    }
  }

  // 通用方法：构建菜单项
  Widget buildListTile({
    required IconData icon,
    required String title,
    required int index,
    required VoidCallback onTap,
  }) {
    return FocusableItem(
      focusNode: _focusNodes[index + 1], // 菜单的FocusNode从索引1开始
      child: ListTile(
        leading: Icon(icon), // 图标
        title: Text(
          title,
          style: const TextStyle(fontSize: 22), // 设置文字大小
        ), // 标题
        selected: _selectedIndex == index, // 判断是否选中
        selectedTileColor: selectedColor, // 选中时背景颜色
        tileColor: _focusNodes[index + 1].hasFocus
            ? darkenColor(_selectedIndex == index ? selectedColor : Colors.transparent) // 聚焦时变暗颜色
            : (_selectedIndex == index ? selectedColor : null), // 未选中时默认颜色
        onTap: () {
          if (_selectedIndex != index) {
            setState(() {
              _selectedIndex = index; // 更新选中项索引
              _confirmedIndex = index; // 用户按下确认键后更新右侧页面索引
            });
          }
          onTap(); // 触发传入的 onTap 事件
        },
      ),
    );
  }

  // 根据确认选择的索引构建右侧页面
  Widget _buildRightPanel() {
    switch (_confirmedIndex) {
      case 0:
        return const SubScribePage(); // 订阅页面
      case 1:
        return const SettingFontPage(); // 字体设置页面
      case 2:
        return const SettingBeautifyPage(); // 美化设置页面
      case 3:
        return SettinglogPage(); // 日志页面
      case 4:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png', // 本地图像资源替换
                width: 98, // 图像宽度
                height: 98, // 图像高度
              ),
              const SizedBox(height: 18),
              Text(
                S.of(context).checkUpdate,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      default:
        return Container(); // 空页面，避免未匹配的索引时出错
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前语言
    final languageProvider = Provider.of<LanguageProvider>(context);

    // 使用 FocusScope 包裹父页面的 TvKeyNavigation，确保父子页面焦点隔离
    return FocusScope(
      child: TvKeyNavigation(
        focusNodes: _focusNodes,
        initialIndex: _selectedIndex + 1, // 初始焦点为菜单项的第一个焦点
        isFrame: true, // 启用框架模式
        frameType: "parent", // 设置为父框架
        isVerticalGroup: true, // 启用竖向分组
        onSelect: (index) {
          setState(() {
            _selectedIndex = index - 1; // 更新选中项索引，减去1与菜单匹配
          });
        },
        child: Row(
          children: [
            // 左侧菜单部分
            SizedBox(
              width: 258,
              child: Group(
                groupIndex: 0, // 菜单分组
                child: Scaffold(
                  appBar: AppBar(
                    leading: FocusableItem(
                      focusNode: _focusNodes[0], // 返回按钮的 FocusNode
                      child: ListTile(
                        leading: Icon(
                          Icons.arrow_back,
                          color: _focusNodes[0].hasFocus ? darkenColor(selectedColor) : Colors.white, // 焦点时改变颜色
                        ),
                        onTap: () {
                          Navigator.of(context).pop(); // 返回到上一个页面
                        },
                      ),
                    ),
                    title: Consumer<LanguageProvider>(
                      builder: (context, languageProvider, child) {
                        return Text(
                          S.of(context).settings, // 页面标题
                          style: const TextStyle(
                            fontSize: 22, // 设置字号
                            fontWeight: FontWeight.bold, // 设置加粗
                          ),
                        );
                      },
                    ),
                  ),
                  // 使用 Group 包裹所有 FocusableItem 分组
                  body: Column(
                    children: [
                      buildListTile(
                        icon: Icons.subscriptions,
                        title: S.of(context).subscribe, // 订阅
                        index: 0,
                        onTap: () {
                          setState(() {
                            _selectedIndex = 0;
                            _confirmedIndex = 0; // 用户按下确认键后更新页面
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.font_download,
                        title: S.of(context).fontTitle, // 字体
                        index: 1,
                        onTap: () {
                          setState(() {
                            _selectedIndex = 1;
                            _confirmedIndex = 1; // 用户按下确认键后更新页面
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.brush,
                        title: S.of(context).backgroundImageTitle, // 背景图
                        index: 2,
                        onTap: () {
                          setState(() {
                            _selectedIndex = 2;
                            _confirmedIndex = 2; // 用户按下确认键后更新页面
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.view_list,
                        title: S.of(context).slogTitle, // 日志
                        index: 3,
                        onTap: () {
                          setState(() {
                            _selectedIndex = 3;
                            _confirmedIndex = 3; // 用户按下确认键后更新页面
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.system_update,
                        title: S.of(context).updateTitle, // 更新
                        index: 4,
                        onTap: () {
                          setState(() {
                            _selectedIndex = 4;
                            _confirmedIndex = 4; // 用户按下确认键后更新页面
                          });
                          _checkForUpdates(); // 调用检查更新逻辑
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 右侧页面显示，默认显示根据初始索引的页面
            Expanded(
              child: _buildRightPanel(), // 根据用户确认选择的索引显示页面
            ),
          ],
        ),
      ),
    );
  }
}
