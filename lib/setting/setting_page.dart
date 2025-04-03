import 'package:flutter/material.dart'; 
import 'package:provider/provider.dart'; 
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/router_keys.dart'; 
import 'package:itvapp_live_tv/util/check_version_util.dart'; 
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart'; 
import 'package:itvapp_live_tv/config.dart'; 

// 设置页面的主类，继承自 StatefulWidget，用于管理动态状态
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState(); // 创建并返回状态类实例
}

// 设置页面的状态类，负责页面逻辑和 UI 更新
class _SettingPageState extends State<SettingPage> {
  // 定义静态常量样式，避免重复创建 TextStyle 对象以提升性能
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

  // 存储最新版本信息，可能为 null，由版本检查工具提供
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity;

  // 缓存容器宽度，避免重复计算以优化性能
  late double _containerWidth;

  @override
  void initState() {
    super.initState();
    // 初始化时计算容器宽度，仅执行一次
    _containerWidth = _calculateContainerWidth();
  }

  // 计算容器宽度，限制最大宽度为 580，适配不同屏幕尺寸
  double _calculateContainerWidth() {
    var screenWidth = MediaQuery.of(context).size.width;
    double maxContainerWidth = 580;
    return screenWidth > maxContainerWidth ? maxContainerWidth : double.infinity;
  }

  // 监听依赖变化（如语言），确保页面内容同步更新
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 检查挂载状态，避免在未挂载时调用 setState
    if (mounted) {
      // 当前依赖 Consumer 自动更新，无需额外逻辑
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<LanguageProvider>(
          builder: (context, languageProvider, child) {
            return Text(
              S.of(context).settings,  // 显示“设置”标题，随语言动态更新
              style: _titleTextStyle,   // 应用预定义标题样式
            );
          },
        ),
      ),
      body: ListView(
        children: [
          Column(
            children: [
              const SizedBox(height: 20), // 顶部留白，增强视觉层次
              Image.asset(
                'assets/images/logo.png', // 显示应用 Logo
                width: MediaQuery.of(context).orientation == Orientation.portrait ? 80 : 68, // 适配屏幕方向
              ),
              const SizedBox(height: 12), // Logo 与名称间距
              Stack(
                clipBehavior: Clip.none, 
                children: [
                  Text(
                    S.of(context).appName, // 显示应用名称，随语言更新
                    style: _titleTextStyle, // 应用预定义标题样式
                  ),
                  Positioned(
                    top: 0,
                    right: -45, // 版本号定位，右移避免重叠
                    child: Text(
                      'v${Config.version}', // 显示当前版本号
                      style: _versionTextStyle, // 应用预定义版本样式
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18), // 内容与选项列表间距
            ],
          ),
          buildSettingOption(
            icon: Icons.home_filled,
            title: S.of(context).homePage, // “主页”选项
            containerWidth: _containerWidth,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.homeLink); // 打开主页链接
            },
          ),
          buildSettingOption(
            icon: Icons.history,
            title: S.of(context).releaseHistory, // “发布历史”选项
            containerWidth: _containerWidth,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(CheckVersionUtil.releaseLink); // 打开发布历史链接
            },
          ),
          buildSettingOption(
            icon: Icons.tips_and_updates,
            title: S.of(context).checkUpdate, // “检查更新”选项
            containerWidth: _containerWidth,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_latestVersionEntity != null) // 显示新版本提示（若存在）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEB144C),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      S.of(context).newVersion(_latestVersionEntity!.latestVersion!), // 显示最新版本号
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_right), // 默认右箭头
              ],
            ),
            onTap: () async {
              // 检查版本更新并刷新状态
              await CheckVersionUtil.checkVersion(context, true, true, true);
              if (mounted) {
                setState(() {
                  _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 更新版本信息
                });
              }
              // 若无新版本，显示提示
              if (_latestVersionEntity == null) {
                CustomSnackBar.showSnackBar(
                  context,
                  S.of(context).latestVersion, // “已是最新版本”
                  duration: const Duration(seconds: 4),
                );
              }
            },
          ),
          buildSettingOption(
            icon: Icons.text_fields,
            title: S.of(context).fontTitle, // “字体设置”选项
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingFont); // 跳转字体设置页
            },
          ),
          buildSettingOption(
            icon: Icons.ac_unit,
            title: S.of(context).backgroundImageTitle, // “背景图片”选项
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settingBeautify); // 跳转背景设置页
            },
          ),
          buildSettingOption(
            icon: Icons.view_list,
            title: S.of(context).slogTitle, // “日志”选项
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.settinglog); // 跳转日志页
            },
          ),
        ],
      ),
    );
  }

  // 构建设置选项的通用方法，生成可复用的 ListTile 组件
  Widget buildSettingOption({
    required IconData icon,        // 选项图标
    required String title,        // 选项标题
    required double containerWidth, // 容器宽度
    required Function onTap,      // 点击回调
    Widget? trailing,             // 右侧组件，默认为箭头
  }) {
    return Container(
      width: containerWidth, // 控制选项宽度
      padding: const EdgeInsets.symmetric(horizontal: 16), // 左右内边距
      child: ListTile(
        title: Text(
          title,
          style: _optionTextStyle, // 应用预定义选项样式
        ),
        leading: Icon(icon),        // 左侧图标
        trailing: trailing ?? const Icon(Icons.arrow_right), // 右侧组件
        onTap: () => onTap(),       // 执行点击回调
      ),
    );
  }
}
