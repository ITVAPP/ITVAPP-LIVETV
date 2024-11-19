import 'package:flutter/material.dart'; 
import 'package:provider/provider.dart'; 
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/router_keys.dart'; 
import 'package:itvapp_live_tv/util/check_version_util.dart'; 
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import '../generated/l10n.dart'; 
import '../config.dart'; 

// 设置页面的主类，继承自 StatefulWidget
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState(); // 返回 _SettingPageState 状态类实例
}

// 设置页面的状态类
class _SettingPageState extends State<SettingPage> {
  // 静态常量样式定义，避免重复创建TextStyle对象
  static const _titleTextStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );
  
  static const _versionTextStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFFEB144C),
    fontWeight: FontWeight.bold,
  );

  static const _optionTextStyle = TextStyle(fontSize: 18);

  // 存储最新的版本信息，通过版本检查工具获取
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity;

  // 缓存容器宽度计算结果
  late double _containerWidth;

  // 当系统语言或其他依赖项发生变化时调用该方法，强制页面重建以更新显示
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 计算并缓存容器宽度
    var screenWidth = MediaQuery.of(context).size.width;
    double maxContainerWidth = 580;
    _containerWidth = screenWidth > maxContainerWidth ? maxContainerWidth : double.infinity;
    
    setState(() {
      // 通过 setState 触发页面重建，确保语言切换时即时更新UI
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<LanguageProvider>(
          builder: (context, languageProvider, child) {
            return Text(
              S.of(context).settings,  // AppBar 的标题
              style: _titleTextStyle, // 使用提取的静态样式
            );
          },
        ),
      ),
      body: ListView(
        children: [
          Column(
            children: [
              const SizedBox(height: 20), // 顶部留白
              Image.asset(
                'assets/images/logo.png', // 加载并显示应用的 Logo
                // 根据屏幕方向设置不同的宽度
                width: MediaQuery.of(context).orientation == Orientation.portrait ? 80 : 68,
              ),
              const SizedBox(height: 12), // Logo 与应用名称之间的间距
              Stack(
                clipBehavior: Clip.none, 
                children: [
                  Text(
                    S.of(context).appName, // 显示应用名称
                    style: _titleTextStyle, // 使用提取的静态样式
                  ),
                  Positioned(
                    top: 0,
                    right: -45, // 版本号右移 -45，确保与文本分离
                    child: Text(
                      'v${Config.version}', // 获取当前应用版本号
                      style: _versionTextStyle, // 使用提取的静态样式
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18), // 内容与列表之间的间距
            ],
          ),
          buildSettingOption(
            icon: Icons.home_filled,
            title: S.of(context).homePage,
            containerWidth: _containerWidth, // 使用缓存的容器宽度
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.homeLink);
            },
          ),
          buildSettingOption(
            icon: Icons.history,
            title: S.of(context).releaseHistory,
            containerWidth: _containerWidth,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.releaseLink);
            },
          ),
          buildSettingOption(
            icon: Icons.tips_and_updates,
            title: S.of(context).checkUpdate,
            containerWidth: _containerWidth,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_latestVersionEntity != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEB144C),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      S.of(context).newVersion(_latestVersionEntity!.latestVersion!),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_right),
              ],
            ),
            onTap: () async {
              await CheckVersionUtil.checkVersion(context, true, true, true);
              if (mounted) {
                setState(() {
                  _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
                });
              }

              if (_latestVersionEntity == null) {
                CustomSnackBar.showSnackBar(
                  context,
                  S.of(context).latestVersion,
                  duration: const Duration(seconds: 4),
                );
              }
            },
          ),
          buildSettingOption(
            icon: Icons.text_fields,
            title: S.of(context).fontTitle,
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingFont);
            },
          ),
          buildSettingOption(
            icon: Icons.ac_unit,
            title: S.of(context).backgroundImageTitle,
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingBeautify);
            },
          ),
          buildSettingOption(
            icon: Icons.view_list,
            title: S.of(context).slogTitle,
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settinglog);
            },
          ),
        ],
      ),
    );
  }

  // 公共设置项构建方法
  Widget buildSettingOption({
    required IconData icon,
    required String title,
    required double containerWidth,
    required Function onTap,
    Widget? trailing,
  }) {
    return Center(
      child: Container(
        width: containerWidth,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListTile(
          title: Text(
            title,
            style: _optionTextStyle, // 使用提取的静态样式
          ),
          leading: Icon(icon),
          trailing: trailing ?? const Icon(Icons.arrow_right),
          onTap: () => onTap(),
        ),
      ),
    );
  }
}
