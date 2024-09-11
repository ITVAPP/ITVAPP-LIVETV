import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:flutter/material.dart';
import '../setting/setting_beautify_page.dart';
import '../util/log_util.dart';

class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key});

  @override
  State<TvSettingPage> createState() => _TvSettingPageState();
}

class _TvSettingPageState extends State<TvSettingPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
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
                    }, '点击订阅源时发生错误');
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
                    }, '点击字体设置时发生错误');
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
                    }, '点击美化时发生错误');
                  },
                ),
              ],
            ),
          ),
        ),
        if (_selectedIndex == 0)
          LogUtil.safeExecute(
            () => const Expanded(child: SubScribePage()),
            '加载订阅源页面时发生错误',
          ),
        if (_selectedIndex == 1)
          LogUtil.safeExecute(
            () => const Expanded(child: SettingFontPage()),
            '加载字体设置页面时发生错误',
          ),
        if (_selectedIndex == 2)
          LogUtil.safeExecute(
            () => const Expanded(child: SettingBeautifyPage()),
            '加载美化页面时发生错误',
          ),
      ],
    );
  }
}
