import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:flutter/material.dart';
import '../setting/setting_beautify_page.dart';
import '../util/log_util.dart';  // 引入日志工具类

class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key});

  @override
  State<TvSettingPage> createState() => _TvSettingPageState();
}

class _TvSettingPageState extends State<TvSettingPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return LogUtil.safeExecute<Widget>(() {
      return Row(
        children: [
          SizedBox(
            width: 300,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('设置'),
              ),
              body: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.subscriptions),
                    title: const Text('订阅源'),
                    selected: _selectedIndex == 0,
                    autofocus: true,
                    onTap: () {
                      LogUtil.safeExecute(() {
                        setState(() {
                          _selectedIndex = 0;
                        });
                        LogUtil.v('选择了订阅源设置');
                      }, '选择订阅源设置时发生错误');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.font_download),
                    title: const Text('字体设置'),
                    selected: _selectedIndex == 1,
                    onTap: () {
                      LogUtil.safeExecute(() {
                        setState(() {
                          _selectedIndex = 1;
                        });
                        LogUtil.v('选择了字体设置');
                      }, '选择字体设置时发生错误');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: const Text('美化'),
                    selected: _selectedIndex == 2,
                    onTap: () {
                      LogUtil.safeExecute(() {
                        setState(() {
                          _selectedIndex = 2;
                        });
                        LogUtil.v('选择了美化设置');
                      }, '选择美化设置时发生错误');
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_selectedIndex == 0)
            const Expanded(
              child: SubScribePage(),
            ),
          if (_selectedIndex == 1)
            const Expanded(
              child: SettingFontPage(),
            ),
          if (_selectedIndex == 2)
            const Expanded(
              child: SettingBeautifyPage(),
            ),
        ],
      );
    }, '构建设置页面时发生错误');
  }
}
