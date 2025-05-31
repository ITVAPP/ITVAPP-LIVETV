import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 关于页面的主类，继承自 StatefulWidget，用于管理动态状态
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

// 关于页面的状态类，负责页面逻辑和 UI 更新
class _AboutPageState extends State<AboutPage> {
  // 定义静态常量样式，复用设置页面的样式规范
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

  static const _urlTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.grey,
  );

  static const _recordTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.grey,
  );

  // 默认的箭头图标
  static const _defaultTrailing = Icon(Icons.arrow_right);

  // 复制按钮图标
  static const _copyTrailing = Icon(Icons.copy, size: 20, color: Colors.grey);

  // 缓存容器宽度，避免重复计算以优化性能
  late double _containerWidth;
  late double _screenWidth;
  late Orientation _orientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _orientation = mediaQuery.orientation;
    _containerWidth = _calculateContainerWidth();
  }

  // 计算容器宽度，复用设置页面的计算逻辑
  double _calculateContainerWidth() {
    double maxContainerWidth = 580;
    return _screenWidth > maxContainerWidth ? maxContainerWidth : _screenWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).aboutApp, // 关于应用
          style: _titleTextStyle,
        ),
      ),
      body: ListView(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              // 应用图标
              Image.asset(
                'assets/images/logo.png',
                width: _orientation == Orientation.portrait ? 80 : 68,
              ),
              const SizedBox(height: 12),
              // 应用名称和版本号
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
              const SizedBox(height: 8),
              // ICP备案信息（如果有的话）
              Text(
                Config.icpRecord ?? '', // 需要在Config中添加ICP备案号配置
                style: _recordTextStyle,
              ),
              const SizedBox(height: 18),
            ],
          ),
          // 访问官网选项
          _buildAboutOption(
            icon: Icons.home_filled,
            title: S.of(context).officialWebsite, // 官网
            subtitle: Config.homeUrl ?? CheckVersionUtil.homeLink, // 官网地址
            containerWidth: _containerWidth,
            trailing: _defaultTrailing,
            onTap: () {
              CheckVersionUtil.launchBrowserUrl(Config.homeUrl ?? CheckVersionUtil.homeLink);
            },
          ),
          // 官方邮箱选项
          _buildAboutOption(
            icon: Icons.email,
            title: S.of(context).officialEmail, // 官方邮箱
            subtitle: Config.officialEmail ?? 'feedback@example.com', // 官方邮箱地址
            containerWidth: _containerWidth,
            trailing: _copyTrailing,
            onTap: () => _copyToClipboard(
              Config.officialEmail ?? 'feedback@example.com',
              S.of(context).emailCopied, // 邮箱地址已复制
            ),
          ),
          // 算法推荐专项举报邮箱（如果需要的话）
          if (Config.algorithmReportEmail != null)
            _buildAboutOption(
              icon: Icons.report,
              title: S.of(context).algorithmReport, // 算法推荐专项举报
              subtitle: Config.algorithmReportEmail!,
              containerWidth: _containerWidth,
              trailing: _copyTrailing,
              onTap: () => _copyToClipboard(
                Config.algorithmReportEmail!,
                S.of(context).emailCopied,
              ),
            ),
          // 违规举报邮箱（如果需要的话）
          if (Config.violationReportEmail != null)
            _buildAboutOption(
              icon: Icons.warning,
              title: S.of(context).violationReport, // 违法违规行为举报
              subtitle: Config.violationReportEmail!,
              containerWidth: _containerWidth,
              trailing: _copyTrailing,
              onTap: () => _copyToClipboard(
                Config.violationReportEmail!,
                S.of(context).emailCopied,
              ),
            ),
        ],
      ),
    );
  }

  // 构建关于页面选项的通用方法，生成可复用的 ListTile 组件
  Widget _buildAboutOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required double containerWidth,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Container(
      width: containerWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          title,
          style: _optionTextStyle,
        ),
        subtitle: Text(
          subtitle,
          style: _urlTextStyle,
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  // 复制到剪贴板的方法，包含完整的错误处理
  Future<void> _copyToClipboard(String text, String successMessage) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          successMessage,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).copyFailed, // 复制失败
          duration: const Duration(seconds: 2),
        );
      }
    }
  }
}
