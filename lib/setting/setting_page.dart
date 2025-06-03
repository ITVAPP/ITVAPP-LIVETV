import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 设置页面主类
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

// 设置页面状态类
class _SettingPageState extends State<SettingPage> {
  // 定义静态样式
  static const _titleTextStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  // 版本号样式
  static const _versionTextStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFFEB144C),
    fontWeight: FontWeight.bold,
  );

  // 选项文本样式
  static const _optionTextStyle = TextStyle(fontSize: 18);

  // 默认箭头图标
  static const _defaultTrailing = Icon(Icons.arrow_right);

  // 存储最新版本信息，可为null
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity;

  // 缓存容器宽度
  late double _containerWidth;

  // 缓存屏幕宽度和方向
  late double _screenWidth;
  late Orientation _orientation;

  @override
  void initState() {
    super.initState();
  }

  // 初始化MediaQuery，保障context安全
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _orientation = mediaQuery.orientation;
    _containerWidth = _calculateContainerWidth();
  }

  // 计算容器宽度，限制最大580
  double _calculateContainerWidth() {
    double maxContainerWidth = 580;
    return _screenWidth > maxContainerWidth ? maxContainerWidth : _screenWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).settings,
          style: _titleTextStyle,
        ),
      ),
      body: ListView(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              Image.asset(
                'assets/images/logo.png',
                width: _orientation == Orientation.portrait ? 80 : 68,
              ),
              const SizedBox(height: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(
                    S.of(context).appName,
                    style: _titleTextStyle,
                  ),
                  Positioned(
                    top: 0,
                    right: -(_screenWidth * 0.12),
                    child: Text(
                      'v${Config.version}',
                      style: _versionTextStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ),
          buildSettingOption(
            icon: Icons.info,
            title: S.of(context).aboutApp,
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.about);
            },
          ),
          buildSettingOption(
            icon: Icons.description,
            title: S.of(context).userAgreement,
            containerWidth: _containerWidth,
            onTap: () {
              Navigator.pushNamed(context, RouterKeys.agreement);
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
                _defaultTrailing,
              ],
            ),
            onTap: () async {
              await CheckVersionUtil.checkVersion(context, true, true, true);
              if (mounted) {
                setState(() {
                  _latestVersionEntity = CheckVersionUtil.latestVersionEntity;
                });
                if (_latestVersionEntity == null) {
                  CustomSnackBar.showSnackBar(
                    context,
                    S.of(context).latestVersion,
                    duration: const Duration(seconds: 4),
                  );
                }
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

  // 构建通用设置选项
  Widget buildSettingOption({
    required IconData icon,
    required String title,
    required double containerWidth,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Container(
      width: containerWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        title: Text(
          title,
          style: _optionTextStyle,
        ),
        leading: Icon(icon),
        trailing: trailing ?? _defaultTrailing,
        onTap: onTap,
      ),
    );
  }
}
