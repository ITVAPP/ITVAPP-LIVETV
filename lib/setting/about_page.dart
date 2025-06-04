import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 管理焦点状态
class SelectionState {
  final int focusedIndex; // 聚焦选项索引

  SelectionState(this.focusedIndex);

  // 比较状态，减少无效更新
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is SelectionState &&
    runtimeType == other.runtimeType &&
    focusedIndex == other.focusedIndex;

  @override
  int get hashCode => focusedIndex.hashCode;
}

// 关于页面主类
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

// 关于页面状态类
class _AboutPageState extends State<AboutPage> {
  // 页面标题样式
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  // 应用名称样式
  static const _titleTextStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  // 版本号样式
  static const _versionTextStyle = TextStyle(fontSize: 13, color: Color(0xFFEB144C), fontWeight: FontWeight.bold);
  // 选项文本样式
  static const _optionTextStyle = TextStyle(fontSize: 18);
  // 备案信息样式
  static const _recordTextStyle = TextStyle(fontSize: 14, color: Colors.grey);
  // 容器最大宽度
  static const _maxContainerWidth = 580.0;

  // 定义AppBar分割线样式
  static final _appBarDivider = PreferredSize(
    preferredSize: const Size.fromHeight(1),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    ),
  );

  // 定义AppBar装饰样式
  static final _appBarDecoration = BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        spreadRadius: 2,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // 选中背景色（红色）
  final _selectedColor = const Color(0xFFEB144C);
  // 未选中背景色（黄色）
  final _unselectedColor = const Color(0xFFDFA02A);

  // 管理可交互元素焦点节点
  late final List<FocusNode> _focusNodes;

  // 分组焦点缓存，优化TV导航
  late final Map<int, Map<String, FocusNode>> _groupFocusCache;

  // 关于页面选择状态
  late SelectionState _aboutState;

  @override
  void initState() {
    super.initState();

    // 初始化焦点节点，避开initState使用context
    const maxTotalOptions = 4;

    _focusNodes = List<FocusNode>.generate(maxTotalOptions, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange);
      return node;
    });

    // 默认无焦点状态
    _aboutState = SelectionState(-1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 初始化分组焦点缓存
    _groupFocusCache = _generateGroupFocusCache();
  }

  // 计算实际选项数量
  int _getActiveOptionsCount() {
    int count = 2;
    if (Config.algorithmReportEmail != null) count++;
    if (_isChineseLanguage()) count++;
    return count;
  }

  // 生成分组焦点缓存
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache() {
    final cache = <int, Map<String, FocusNode>>{};
    final activeOptionsCount = _getActiveOptionsCount();
    
    cache[0] = {
      'firstFocusNode': _focusNodes[0],
      'lastFocusNode': _focusNodes[activeOptionsCount - 1],
    };

    return cache;
  }

  // 处理焦点变化，减少无效更新
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      final newAboutState = SelectionState(focusedIndex);
      if (newAboutState != _aboutState) {
        if (mounted) {
          setState(() {
            _aboutState = newAboutState;
          });
        }
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          final newAboutState = SelectionState(newFocusedIndex);
          if (newAboutState != _aboutState) {
            setState(() {
              _aboutState = newAboutState;
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    if (mounted) {
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange);
        node.dispose();
      }
    }
    super.dispose();
  }

  // 检查是否为中文语言
  bool _isChineseLanguage() {
    final currentLocale = context.read<LanguageProvider>().currentLocale.toString();
    return currentLocale.startsWith('zh');
  }

  // 打开应用商店评分
  Future<void> _openAppStore() async {
    try {
      String url;
      if (Platform.isAndroid) {
        url = 'market://details?id=${Config.packagename}';
        final fallbackUrl = 'https://play.google.com/store/apps/details?id=${Config.packagename}';
        
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          await launch(fallbackUrl);
        }
      } else if (Platform.isIOS) {
        if (Config.appStoreId == null) {
          if (mounted) {
            CustomSnackBar.showSnackBar(
              context,
              S.of(context).openAppStoreFailed,
              duration: const Duration(seconds: 3),
            );
          }
          return;
        }
        
        url = 'itms-apps://apps.apple.com/app/id${Config.appStoreId}';
        final fallbackUrl = 'https://apps.apple.com/app/id${Config.appStoreId}';
        
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          await launch(fallbackUrl);
        }
      } else {
        if (mounted) {
          CustomSnackBar.showSnackBar(
            context,
            S.of(context).platformNotSupported,
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }

      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).openingAppStore,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).openAppStoreFailed,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  // 复制文本到剪贴板
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
          S.of(context).copyFailed,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;
    
    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48.0,
        centerTitle: true,
        automaticallyImplyLeading: !isTV,
        title: Text(
          S.of(context).aboutApp,
          style: _titleStyle,
        ),
        bottom: _appBarDivider,
        flexibleSpace: Container(
          decoration: _appBarDecoration,
        ),
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes.sublist(0, _getActiveOptionsCount()),
          groupFocusCache: _groupFocusCache,
          isVerticalGroup: true,
          initialIndex: 0,
          isFrame: isTV ? true : false,
          frameType: isTV ? "child" : null,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth > _maxContainerWidth ? _maxContainerWidth : double.infinity,
              ),
              child: ListView(
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      Image.asset(
                        'assets/images/logo.png',
                        width: orientation == Orientation.portrait ? 80 : 68,
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
                            right: -(screenWidth * 0.12),
                            child: Text(
                              'v${Config.version}',
                              style: _versionTextStyle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (Config.icpRecord?.isNotEmpty == true)
                        Text(
                          Config.icpRecord!,
                          style: _recordTextStyle,
                        ),
                      const SizedBox(height: 18),
                    ],
                  ),
                  AboutOptionsSection(
                    focusNodes: _focusNodes,
                    state: _aboutState,
                    selectedColor: _selectedColor,
                    unselectedColor: _unselectedColor,
                    onWebsiteTap: () {
                      CheckVersionUtil.launchBrowserUrl(Config.homeUrl ?? CheckVersionUtil.homeLink);
                    },
                    onRateTap: _openAppStore,
                    onEmailTap: () => _copyToClipboard(
                      Config.officialEmail,
                      S.of(context).emailCopied,
                    ),
                    onBusinessTap: Config.algorithmReportEmail != null
                        ? () => _copyToClipboard(
                            Config.algorithmReportEmail!,
                            S.of(context).emailCopied,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 关于页面选项组件
class AboutOptionsSection extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final SelectionState state;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onWebsiteTap;
  final VoidCallback onRateTap;
  final VoidCallback onEmailTap;
  final VoidCallback? onBusinessTap;

  const AboutOptionsSection({
    super.key,
    required this.focusNodes,
    required this.state,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onWebsiteTap,
    required this.onRateTap,
    required this.onEmailTap,
    this.onBusinessTap,
  });

  // 检查是否为中文语言
  bool _isChineseLanguage(BuildContext context) {
    final currentLocale = context.read<LanguageProvider>().currentLocale.toString();
    return currentLocale.startsWith('zh');
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> options = [];
    int focusIndex = 0;

    final List<Widget> groupChildren = [];

    // 官网选项
    groupChildren.add(
      _buildOptionItem(
        context: context,
        focusNode: focusNodes[focusIndex],
        icon: Icons.home_filled,
        title: S.of(context).officialWebsite,
        subtitle: Config.homeUrl ?? CheckVersionUtil.homeLink,
        trailing: const Icon(Icons.arrow_right),
        isFocused: state.focusedIndex == focusIndex,
        onTap: onWebsiteTap,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
      ),
    );
    focusIndex++;

    // 应用商店评分选项（仅中文）
    if (_isChineseLanguage(context)) {
      groupChildren.add(
        _buildOptionItem(
          context: context,
          focusNode: focusNodes[focusIndex],
          icon: Icons.star_rate,
          title: S.of(context).rateApp,
          subtitle: S.of(context).rateAppDescription,
          trailing: const Icon(Icons.star, size: 20, color: Color(0xFFEB144C)),
          isFocused: state.focusedIndex == focusIndex,
          onTap: onRateTap,
          selectedColor: selectedColor,
          unselectedColor: unselectedColor,
        ),
      );
      focusIndex++;
    }

    // 反馈邮箱选项
    groupChildren.add(
      _buildOptionItem(
        context: context,
        focusNode: focusNodes[focusIndex],
        icon: Icons.email,
        title: S.of(context).officialEmail,
        subtitle: Config.officialEmail,
        trailing: const Icon(Icons.copy, size: 20, color: Colors.grey),
        isFocused: state.focusedIndex == focusIndex,
        onTap: onEmailTap,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
      ),
    );
    focusIndex++;

    // 合作邮箱选项
    if (Config.algorithmReportEmail != null && onBusinessTap != null) {
      groupChildren.add(
        _buildOptionItem(
          context: context,
          focusNode: focusNodes[focusIndex],
          icon: Icons.report,
          title: S.of(context).algorithmReport,
          subtitle: Config.algorithmReportEmail!,
          trailing: const Icon(Icons.copy, size: 20, color: Colors.grey),
          isFocused: state.focusedIndex == focusIndex,
          onTap: onBusinessTap!,
          selectedColor: selectedColor,
          unselectedColor: unselectedColor,
        ),
      );
    }

    options.add(
      Group(
        groupIndex: 0,
        children: groupChildren,
      ),
    );

    return Column(children: options);
  }

  // 构建选项项，统一样式和交互
  Widget _buildOptionItem({
    required BuildContext context,
    required FocusNode focusNode,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required bool isFocused,
    required VoidCallback onTap,
    required Color selectedColor,
    required Color unselectedColor,
  }) {
    // 计算焦点状态颜色
    Color backgroundColor = isFocused ? darkenColor(unselectedColor) : Colors.transparent;
    Color borderColor = isFocused ? selectedColor : Colors.transparent;
    
    return FocusableItem(
      focusNode: focusNode,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: ListTile(
          leading: Icon(
            icon,
            color: isFocused ? selectedColor : null,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: isFocused ? Colors.white : null,
              fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: isFocused ? Colors.white70 : Colors.grey,
            ),
          ),
          trailing: trailing,
          onTap: onTap,
        ),
      ),
    );
  }
}
