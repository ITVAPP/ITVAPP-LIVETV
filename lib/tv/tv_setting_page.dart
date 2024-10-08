import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:itvapp_live_tv/setting/setting_beautify_page.dart';
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key});

  @override
  State<TvSettingPage> createState() => _TvSettingPageState();
}

class _TvSettingPageState extends State<TvSettingPage> {
  int _selectedIndex = 0; // 当前选中的菜单索引，初始值为0
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 存储最新版本信息
  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode()); // 创建焦点节点列表

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初始化时为第一个菜单项设置焦点
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    try {
      await CheckVersionUtil.checkVersion(context, true, true, true);
      setState(() {
        _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
      });

      if (_latestVersionEntity != null) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).newVersion(_latestVersionEntity!.latestVersion!),
          duration: Duration(seconds: 4),
        );
      } else {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).latestVersion,
          duration: Duration(seconds: 4),
        );
      }
    } catch (e) {
      CustomSnackBar.showSnackBar(
        context,
        S.of(context).netReceiveTimeout,
        duration: Duration(seconds: 4),
      );
    }
  }

  Widget buildListTile({
    required IconData icon,
    required String title,
    required int index,
    required VoidCallback onTap,
  }) {
    return FocusableItem(
      focusNode: _focusNodes[index], // 为每个列表项分配焦点节点
      child: ListTile(
        leading: Icon(icon), // 图标
        title: Text(
          title,
          style: const TextStyle(fontSize: 20), // 设置文字大小为20
        ), // 标题
        selected: _selectedIndex == index, // 判断是否选中
        onTap: () {
          setState(() {
            _selectedIndex = index; // 更新选中项索引
          });
          onTap(); // 调用传入的点击处理逻辑
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          print('捕获到按键: ${event.logicalKey}'); // 捕获按键事件
        }
      },
      child: TvKeyNavigation(
        focusNodes: _focusNodes,
        initialIndex: _selectedIndex,
        onSelect: (index) {
          setState(() {
            _selectedIndex = index; // 同步更新选中索引
          });
        },
        child: Row(
          children: [
            SizedBox(
              width: 300,
              child: Scaffold(
                appBar: AppBar(
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
                body: ListView(
                  children: [
                    buildListTile(
                      icon: Icons.subscriptions,
                      title: S.of(context).subscribe, // 订阅
                      index: 0,
                      onTap: () {
                        setState(() {
                          _selectedIndex = 0;
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
                        });
                      },
                    ),
                    buildListTile(
                      icon: Icons.system_update,
                      title: S.of(context).updateTitle, // 更新
                      index: 4,
                      onTap: _checkForUpdates, // 直接调用检查更新逻辑
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedIndex == 0)
              const Expanded(
                child: SubScribePage(), // 如果选中订阅源，则显示订阅页面
              ),
            if (_selectedIndex == 1)
              const Expanded(child: SettingFontPage()), // 如果选中字体设置，则显示字体设置页面
            if (_selectedIndex == 2)
              const Expanded(child: SettingBeautifyPage()), // 如果选中美化，则显示美化设置页面
            if (_selectedIndex == 3)
              Expanded(child: SettinglogPage()), // 如果选中日志，则显示日志页面
          ],
        ),
      ),
    );
  }
}
