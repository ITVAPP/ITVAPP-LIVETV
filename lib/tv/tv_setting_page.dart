import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../generated/l10n.dart'; 
import 'package:itvapp_live_tv/provider/language_provider.dart'; 
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; 
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart'; 
import 'package:itvapp_live_tv/setting/subscribe_page.dart'; 
import '../setting/setting_beautify_page.dart';
import '../setting/setting_log_page.dart'; 
import 'package:flutter/services.dart';

import 'package:itvapp_live_tv/widgets/tv_key_navigation.dart'; // 引入自定义导航组件

// 定义有状态组件TvSettingPage，表示电视应用的设置主页面
class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key}); // 构造函数，继承父类

  @override
  State<TvSettingPage> createState() => _TvSettingPageState(); // 创建对应的状态类
}

// _TvSettingPageState类用于管理TvSettingPage的状态
class _TvSettingPageState extends State<TvSettingPage> {
  int _selectedIndex = 0; // 当前选中的菜单索引，初始值为0
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 存储最新版本信息

  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode()); // 创建焦点节点列表

  @override
  void dispose() {
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
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
        S.of(context).newVersion(_latestVersionEntity!.latestVersion!),  // 直接传递字符串
        duration: Duration(seconds: 4),
      );
    } else {
      // 没有最新版本
      CustomSnackBar.showSnackBar(
        context,
        S.of(context).latestVersion,  // 直接传递字符串
        duration: Duration(seconds: 4),
      );
    }
  } catch (e) {
    // 版本检查失败
      CustomSnackBar.showSnackBar(
        context,
        S.of(context).netReceiveTimeout,  // 直接传递字符串
        duration: Duration(seconds: 4),
      );
  }
}

  // 通用的buildListTile方法
  Widget buildListTile({
    required IconData icon, 
    required String title, 
    required int index, 
    required VoidCallback onTap
  }) {
    return FocusableItem(
      focusNode: _focusNodes[index], // 为每个列表项分配焦点节点
      isFocused: _selectedIndex == index, // 判断当前是否聚焦
      child: ListTile(
        leading: Icon(icon), // 图标
        title: Text(title), // 标题
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
    // 获取当前语言提供者状态
    final languageProvider = Provider.of<LanguageProvider>(context);

    // 使用 TvKeyNavigation 包裹需要焦点切换的部分
    return TvKeyNavigation(
      focusNodes: _focusNodes,
      initialIndex: _selectedIndex,
      isFrame: true, // 启用框架模式
      loopFocus: true, // 启用循环焦点
      onSelect: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Row(
        children: [
          // 左侧菜单部分，宽度固定为300
          SizedBox(
            width: 300,
            child: Scaffold(
              appBar: AppBar(
                title: Consumer<LanguageProvider>(
                  builder: (context, languageProvider, child) {
                    return Text(S.of(context).settings); 
                  },
                ),
              ),
              body: ListView(
                // 使用buildListTile减少重复的ListTile构造代码
                children: [
                  buildListTile(
                    icon: Icons.subscriptions,
                    title: S.of(context).subscribe,  //订阅
                    index: 0,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 0;
                      });
                    },
                  ),
                  buildListTile(
                    icon: Icons.font_download,
                    title: S.of(context).fontTitle,  //字体
                    index: 1,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 1;
                      });
                    },
                  ),
                  buildListTile(
                    icon: Icons.brush,
                    title: S.of(context).backgroundImageTitle,  //背景图
                    index: 2,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 2;
                      });
                    },
                  ),
                  buildListTile(
                    icon: Icons.view_list,
                    title: S.of(context).slogTitle,  //日志
                    index: 3,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 3;
                      });
                    },
                  ),
                  buildListTile(
                    icon: Icons.system_update,
                    title: S.of(context).updateTitle,  //更新
                    index: 4,
                    onTap: _checkForUpdates, // 直接调用检查更新逻辑
                  ),
                ],
              ),
            ),
          ),
          // 根据选中的索引，动态显示右侧的页面内容
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
    );
  }
}
