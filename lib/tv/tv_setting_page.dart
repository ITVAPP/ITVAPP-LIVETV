// 导入必要的包
import 'package:itvapp_live_tv/setting/setting_font_page.dart'; // 字体设置页面
import 'package:itvapp_live_tv/setting/subscribe_page.dart'; // 订阅页面
import 'package:itvapp_live_tv/util/log_util.dart'; // 日志工具类，用于处理日志的存储和展示
import 'package:itvapp_live_tv/util/check_version_util.dart'; // 导入检查版本的工具类
import 'package:flutter/material.dart'; // Flutter UI框架
import '../setting/setting_beautify_page.dart'; // 美化设置页面
import '../setting/setting_log_page.dart'; // 导入日志页面

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

  // 用于检查版本更新的逻辑
  Future<void> _checkForUpdates() async {
    try {
      await CheckVersionUtil.checkVersion(context, true, true, true);
      setState(() {
        _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
      });
      if (_latestVersionEntity != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发现新版本：${_latestVersionEntity!.latestVersion}'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已经是最新版本'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('版本检查失败，请稍后再试: $e'),
        ),
      );
    }
  }

  // 通用的buildListTile方法，减少重复代码
  Widget buildListTile({
    required IconData icon, 
    required String title, 
    required int index, 
    required VoidCallback onTap
  }) {
    return ListTile(
      leading: Icon(icon), // 图标
      title: Text(title), // 标题
      selected: _selectedIndex == index, // 判断是否选中
      onTap: () {
        setState(() {
          _selectedIndex = index; // 更新选中项索引
        });
        onTap(); // 调用传入的点击处理逻辑
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 主界面的布局，使用Row来水平排列左侧菜单和右侧的设置内容
    return Row(
      children: [
        // 左侧菜单部分，宽度固定为300
        SizedBox(
          width: 300,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('设置'), // 标题栏，显示“设置”
            ),
            body: ListView(
              // 使用buildListTile减少重复的ListTile构造代码
              children: [
                buildListTile(
                  icon: Icons.subscriptions,
                  title: '订阅源',
                  index: 0,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),
                buildListTile(
                  icon: Icons.font_download,
                  title: '字体设置',
                  index: 1,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                ),
                buildListTile(
                  icon: Icons.brush,
                  title: '美化',
                  index: 2,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 2;
                    });
                  },
                ),
                buildListTile(
                  icon: Icons.view_list,
                  title: '日志',
                  index: 3,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 3;
                    });
                  },
                ),
                buildListTile(
                  icon: Icons.system_update,
                  title: '检查版本',
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
          Expanded(child: SettingLogPage()), // 如果选中日志，则显示日志页面
      ],
    );
  }
}
