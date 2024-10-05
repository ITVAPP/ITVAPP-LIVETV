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
  // 存储最新的版本信息，通过版本检查工具获取
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity;

  // 当系统语言或其他依赖项发生变化时调用该方法，强制页面重建以更新显示
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      // 通过 setState 触发页面重建，确保语言切换时即时更新UI
    });
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前设备的屏幕宽度，用于后续的布局调整
    var screenWidth = MediaQuery.of(context).size.width;

    // 设置页面内容的最大宽度（适用于大屏幕设备）
    double maxContainerWidth = 580;
    double containerWidth = screenWidth > maxContainerWidth ? maxContainerWidth : double.infinity;

    return Scaffold(
      appBar: AppBar(
        title: Consumer<LanguageProvider>(
          builder: (context, languageProvider, child) {
          return Text(
            S.of(context).settings,  // AppBar 的标题
            style: const TextStyle(
              fontSize: 20, // 设置字体大小
              fontWeight: FontWeight.bold, // 设置字体加粗
            ),
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
                  // 显示应用名称，使用粗体和较大的字号
                  Text(
                    S.of(context).appName, // 显示应用名称
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // 显示应用版本号，使用 Positioned 定位到应用名称的右侧
                  Positioned(
                    top: 0,
                    right: -45, // 版本号右移 -45，确保与文本分离
                    child: Text(
                      'v${Config.version}', // 获取当前应用版本号
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFEB144C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18), // 内容与列表之间的间距
            ],
          ),
          // 居中显示的设置项，具体宽度根据屏幕尺寸调整
          buildSettingOption(
            icon: Icons.home_filled,
            title: S.of(context).homePage,
            containerWidth: containerWidth,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.homeLink);
            },
          ),
          // 发布历史选项
          buildSettingOption(
            icon: Icons.history,
            title: S.of(context).releaseHistory,
            containerWidth: containerWidth,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.releaseLink);
            },
          ),
          // 检查更新选项
          buildSettingOption(
            icon: Icons.tips_and_updates,
            title: S.of(context).checkUpdate,
            containerWidth: containerWidth,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_latestVersionEntity != null) // 如果存在新版本信息
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Color(0xFFEB144C), 
                      borderRadius: BorderRadius.circular(30), // 设置圆角效果
                    ),
                    // 显示最新版本的提示
                    child: Text(
                      S.of(context).newVersion(_latestVersionEntity!.latestVersion!), // 显示新版本号
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 10), // 新版本信息和箭头图标之间的间距
                const Icon(
                  Icons.arrow_right, 
                ), // 显示向右箭头
              ],
            ),
            onTap: () async {
              await CheckVersionUtil.checkVersion(context, true, true, true);
              if (mounted) { // 在调用 setState 前检查 mounted
                setState(() {
                  _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
                });
              }

              // 如果没有新版本，显示SnackBar提示
              if (_latestVersionEntity == null) {
                CustomSnackBar.showSnackBar(
                  context,
                  S.of(context).latestVersion,  // “当前已是最新版本”的提示
                  duration: const Duration(seconds: 4),
                );
              }
            },
          ),
          // 字体设置选项
          buildSettingOption(
            icon: Icons.text_fields,
            title: S.of(context).fontTitle,
            containerWidth: containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingFont);
            },
          ),
          // 美化设置选项
          buildSettingOption(
            icon: Icons.ac_unit,
            title: S.of(context).backgroundImageTitle,
            containerWidth: containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingBeautify);
            },
          ),
          // 日志设置选项
          buildSettingOption(
            icon: Icons.view_list,
            title: S.of(context).slogTitle,
            containerWidth: containerWidth,
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
            style: TextStyle(fontSize: 18), // 设置字体大小
          ), // 显示标题
          leading: Icon(icon),
          trailing: trailing ?? const Icon(
            Icons.arrow_right, 
          ),
          onTap: () => onTap(),
        ),
      ),
    );
  }
}
