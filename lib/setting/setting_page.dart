import 'package:itvapp_live_tv/router_keys.dart'; // 导入路由键，用于导航
import 'package:itvapp_live_tv/util/check_version_util.dart'; // 导入版本检查工具
import 'package:flutter/material.dart'; // 导入Flutter Material库，用于构建UI
import 'package:provider/provider.dart'; // 用于状态管理
import '../generated/l10n.dart'; // 导入国际化语言资源
import 'package:itvapp_live_tv/provider/language_provider.dart'; // 导入语言提供者

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

    return Scaffold(
      appBar: AppBar(
        title: Consumer<LanguageProvider>(
          builder: (context, languageProvider, child) {
            return Text(S.of(context).settings); // 使用国际化语言资源设置 AppBar 的标题
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
                width: 80, // 设置 Logo 的宽度为 80
              ),
              const SizedBox(height: 12), // Logo 与应用名称之间的间距
              Stack(
                clipBehavior: Clip.none, // 子组件溢出时不裁剪
                children: [
                  // 显示应用名称，使用粗体和较大的字号
                  Text(
                    S.of(context).appName, // 使用国际化语言显示应用名称
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
                      'v${CheckVersionUtil.version}', // 从版本检查工具获取当前应用版本号
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
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
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 大屏设备时限制宽度为 580
              padding: const EdgeInsets.symmetric(horizontal: 16), // 内边距
              child: ListTile(
                title: Text(S.of(context).homePage), // 使用国际化语言显示主页选项
                leading: const Icon(Icons.home_filled), // 显示图标
                trailing: const Icon(Icons.arrow_right), // 显示向右箭头
                onTap: () {
                  // 点击时打开主页链接
                  CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.homeLink);
                },
              ),
            ),
          ),
          // 发布历史选项
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 根据屏幕宽度限制最大宽度
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                title: Text(S.of(context).releaseHistory), // 使用国际化语言显示发布历史标题
                leading: const Icon(Icons.history), // 显示图标
                trailing: const Icon(Icons.arrow_right), // 显示向右箭头
                onTap: () {
                  // 点击时打开发布历史链接
                  CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.releaseLink);
                },
              ),
            ),
          ),
          // 检查更新选项
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 大屏设备时限制宽度
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                title: Text(S.of(context).checkUpdate), // 使用国际化语言显示检查更新标题
                leading: const Icon(Icons.tips_and_updates), // 显示检查更新图标
                trailing: Row(
                  mainAxisSize: MainAxisSize.min, // 使子组件占据最小空间
                  children: [
                    if (_latestVersionEntity != null) // 如果存在新版本信息
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.redAccent, // 设置背景颜色为红色
                          borderRadius: BorderRadius.circular(30), // 设置圆角效果
                        ),
                        // 显示最新版本的提示
                        child: Text(
                          S.of(context).newVersion(_latestVersionEntity!.latestVersion!), // 使用国际化语言显示新版本号
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    const SizedBox(width: 10), // 新版本信息和箭头图标之间的间距
                    const Icon(Icons.arrow_right), // 显示向右箭头
                  ],
                ),
                onTap: () async {
                  // 调用版本检查工具，检查是否有新版本
                  await CheckVersionUtil.checkVersion(context, true, true, true);
                  setState(() {
                    // 更新页面以显示最新的版本信息
                    _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
                  });

                  // 如果没有新版本，显示SnackBar提示
                  if (_latestVersionEntity == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.of(context).latestVersion), // 使用国际化语言显示“当前已是最新版本”的提示
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          // 字体设置选项
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 根据屏幕大小调整宽度
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                title: Text(S.of(context).fontTitle), // 设置标题
                leading: const Icon(Icons.text_fields), // 显示图标
                trailing: const Icon(Icons.arrow_right), // 显示向右箭头
                onTap: () {
                  // 导航到字体设置页面
                  Navigator.pushNamed(context, RouterKeys.settingFont);
                },
              ),
            ),
          ),
          // 美化设置选项
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 大屏时限制最大宽度
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                title: Text(S.of(context).backgroundImageTitle), // 设置标题
                leading: const Icon(Icons.ac_unit), // 显示图标
                trailing: const Icon(Icons.arrow_right), // 显示向右箭头
                onTap: () {
                  // 导航到美化设置页面
                  Navigator.pushNamed(context, RouterKeys.settingBeautify);
                },
              ),
            ),
          ),
          // 日志设置选项
          Center(
            child: Container(
              width: screenWidth > 580 ? maxContainerWidth : double.infinity, // 大屏时限制最大宽度
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                title: Text(S.of(context).slogTitle), // 设置标题
                leading: const Icon(Icons.view_list), // 显示图标
                trailing: const Icon(Icons.arrow_right), // 显示向右箭头
                onTap: () {
                  // 导航到日志设置页面
                  Navigator.pushNamed(context, RouterKeys.settinglog);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
