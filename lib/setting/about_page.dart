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

// SelectionState 类用于管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 当前聚焦的选项索引

  SelectionState(this.focusedIndex);

  // 优化：添加相等性比较，避免无效状态更新
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is SelectionState &&
    runtimeType == other.runtimeType &&
    focusedIndex == other.focusedIndex;

  @override
  int get hashCode => focusedIndex.hashCode;
}

// 关于页面的主类，继承自 StatefulWidget，用于管理动态状态
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

// 关于页面的状态类，负责页面逻辑和 UI 更新
class _AboutPageState extends State<AboutPage> {
  // 定义静态常量样式，提升复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  static const _titleTextStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  static const _versionTextStyle = TextStyle(fontSize: 13, color: Color(0xFFEB144C), fontWeight: FontWeight.bold);
  static const _optionTextStyle = TextStyle(fontSize: 18);
  static const _urlTextStyle = TextStyle(fontSize: 14, color: Colors.grey);
  static const _recordTextStyle = TextStyle(fontSize: 14, color: Colors.grey);
  static const _maxContainerWidth = 580.0; // 容器最大宽度

  // 按钮颜色
  final _selectedColor = const Color(0xFFEB144C); // 选中时的背景色（红色）
  final _unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景色（黄色）

  // 焦点节点列表，管理所有可交互元素的焦点
  late final List<FocusNode> _focusNodes;

  // 分组焦点缓存，用于TV导航优化
  late final Map<int, Map<String, FocusNode>> _groupFocusCache;

  // 管理选择状态
  late SelectionState _aboutState;

  @override
  void initState() {
    super.initState();

    // 按最大可能的选项数量初始化焦点节点（避免在initState中使用context）
    const maxTotalOptions = 4; // 官网 + 评分 + 邮箱 + 商务邮箱

    // 初始化焦点节点
    _focusNodes = List<FocusNode>.generate(maxTotalOptions, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 添加焦点变化监听
      return node;
    });

    // 初始化状态：默认无焦点
    _aboutState = SelectionState(-1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里初始化分组焦点缓存，因为此时context已经可用
    _groupFocusCache = _generateGroupFocusCache();
  }

  // 计算实际使用的选项数量
  int _getActiveOptionsCount() {
    int count = 2; // 基础选项：官网 + 邮箱
    if (Config.algorithmReportEmail != null) count++; // 合作邮箱
    if (_isChineseLanguage()) count++; // 应用商店评分（中文时）
    return count;
  }

  // 生成分组焦点缓存，优化TV导航
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache() {
    final cache = <int, Map<String, FocusNode>>{};
    final activeOptionsCount = _getActiveOptionsCount();
    
    // 为每个选项创建独立的分组（参考LanguageSection模式）
    for (int i = 0; i < activeOptionsCount; i++) {
      cache[i] = {
        'firstFocusNode': _focusNodes[i],
        'lastFocusNode': _focusNodes[i],
      };
    }

    return cache;
  }

  // 优化：处理焦点变化，添加状态比较减少无效更新
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      final newAboutState = SelectionState(focusedIndex);
      // 优化：只有状态实际发生变化时才执行setState
      if (newAboutState != _aboutState) {
        if (mounted) {
          setState(() {
            _aboutState = newAboutState;
          });
        }
      }
    } else {
      // 未找到焦点时延迟检查
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          final newAboutState = SelectionState(newFocusedIndex);
          // 优化：延迟回调中也添加状态比较
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
        node.removeListener(_handleFocusChange); // 移除焦点监听
        node.dispose(); // 释放焦点节点
      }
    }
    super.dispose();
  }

  // 检查是否为中文语言
  bool _isChineseLanguage() {
    final currentLocale = context.read<LanguageProvider>().currentLocale.toString();
    return currentLocale.startsWith('zh');
  }

  // 打开应用商店评分页面
  Future<void> _openAppStore() async {
    try {
      String url;
      if (Platform.isAndroid) {
        // Android - Google Play Store
        url = 'market://details?id=${Config.packagename}';
        // 备用链接，如果没有安装 Play Store 应用
        final fallbackUrl = 'https://play.google.com/store/apps/details?id=${Config.packagename}';
        
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          await launch(fallbackUrl);
        }
      } else if (Platform.isIOS) {
        // iOS - App Store
        // 注意：您需要替换 YOUR_APP_ID 为实际的 App Store ID
        const appId = 'YOUR_APP_ID'; // 替换为真实的 App Store ID
        url = 'itms-apps://apps.apple.com/app/id$appId';
        final fallbackUrl = 'https://apps.apple.com/app/id$appId';
        
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          await launch(fallbackUrl);
        }
      } else {
        // 其他平台，显示提示信息
        if (mounted) {
          CustomSnackBar.showSnackBar(
            context,
            S.of(context).platformNotSupported ?? '当前平台不支持此功能',
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }

      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).openingAppStore ?? '正在打开应用商店...',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).openAppStoreFailed ?? '打开应用商店失败',
          duration: const Duration(seconds: 3),
        );
      }
    }
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
          S.of(context).copyFailed ?? '复制失败',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    
    return Scaffold(
      // 修复：使用Selector精确监听isTV属性，直接返回颜色
      backgroundColor: Selector<ThemeProvider, Color>(
        selector: (context, themeProvider) => themeProvider.isTV ? const Color(0xFF1E2022) : Colors.transparent,
        builder: (context, backgroundColor, child) => backgroundColor,
      ),
      appBar: AppBar(
        // 修复：使用Selector精确监听isTV属性
        leading: Selector<ThemeProvider, bool>(
          selector: (context, themeProvider) => themeProvider.isTV,
          builder: (context, isTV, child) => isTV ? const SizedBox.shrink() : const BackButton(),
        ),
        title: Text(
          S.of(context).aboutApp, // 显示"关于"标题
          style: _titleStyle,
        ),
        // 修复：使用Selector精确监听isTV属性，直接返回颜色
        backgroundColor: Selector<ThemeProvider, Color?>(
          selector: (context, themeProvider) => themeProvider.isTV ? const Color(0xFF1E2022) : null,
          builder: (context, backgroundColor, child) => backgroundColor,
        ),
      ),
      body: FocusScope(
        child: Selector<ThemeProvider, bool>(
          selector: (context, themeProvider) => themeProvider.isTV,
          builder: (context, isTV, child) => TvKeyNavigation(
            focusNodes: _focusNodes, // 绑定焦点节点
            groupFocusCache: _groupFocusCache, // 绑定分组焦点缓存
            isHorizontalGroup: false, // 启用垂直分组导航
            initialIndex: 0, // 初始焦点索引
            isFrame: isTV ? true : false, // TV模式启用框架导航
            frameType: isTV ? "child" : null, // TV模式标记为子页面
            child: Align(
              alignment: Alignment.center, // 内容居中对齐
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: screenWidth > _maxContainerWidth ? _maxContainerWidth : double.infinity, // 限制最大宽度
                ),
                child: ListView(
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 20),
                        // 应用图标
                        Image.asset(
                          'assets/images/logo.png',
                          width: orientation == Orientation.portrait ? 80 : 68,
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
                              right: -(screenWidth * 0.12),
                              child: Text(
                                'v${Config.version}',
                                style: _versionTextStyle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ICP备案信息（如果有的话）
                        if (Config.icpRecord?.isNotEmpty == true)
                          Text(
                            Config.icpRecord!,
                            style: _recordTextStyle,
                          ),
                        const SizedBox(height: 18),
                      ],
                    ),
                    // 选项列表
                    AboutOptionsSection(
                      focusNodes: _focusNodes, // 传递所有焦点节点，组件内部会按需使用
                      state: _aboutState,
                      onWebsiteTap: () {
                        CheckVersionUtil.launchBrowserUrl(Config.homeUrl ?? CheckVersionUtil.homeLink);
                      },
                      onRateTap: _openAppStore,
                      onEmailTap: () => _copyToClipboard(
                        Config.officialEmail,
                        S.of(context).emailCopied ?? '邮箱地址已复制',
                      ),
                      onBusinessTap: Config.algorithmReportEmail != null
                          ? () => _copyToClipboard(
                              Config.algorithmReportEmail!,
                              S.of(context).emailCopied ?? '邮箱地址已复制',
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 无状态组件：关于页面选项部分
class AboutOptionsSection extends StatelessWidget {
  final List<FocusNode> focusNodes; // 焦点节点列表
  final SelectionState state; // 当前选择状态
  final VoidCallback onWebsiteTap; // 官网点击回调
  final VoidCallback onRateTap; // 评分点击回调
  final VoidCallback onEmailTap; // 邮箱点击回调
  final VoidCallback? onBusinessTap; // 商务邮箱点击回调

  const AboutOptionsSection({
    super.key,
    required this.focusNodes,
    required this.state,
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
    int groupIndex = 0;

    // 官网选项
    options.add(
      Group(
        groupIndex: groupIndex, // 分组 0
        children: [
          _buildOptionItem(
            context: context,
            focusNode: focusNodes[focusIndex],
            icon: Icons.home_filled,
            title: S.of(context).officialWebsite ?? '官方网站',
            subtitle: Config.homeUrl ?? CheckVersionUtil.homeLink,
            trailing: const Icon(Icons.arrow_right),
            isFocused: state.focusedIndex == focusIndex,
            onTap: onWebsiteTap,
          ),
        ],
      ),
    );
    focusIndex++;
    groupIndex++;

    // 应用商店评分选项（仅中文语言显示）
    if (_isChineseLanguage(context)) {
      options.add(
        Group(
          groupIndex: groupIndex, // 分组 1（中文时）
          children: [
            _buildOptionItem(
              context: context,
              focusNode: focusNodes[focusIndex],
              icon: Icons.star_rate,
              title: S.of(context).rateApp ?? '应用商店评分',
              subtitle: S.of(context).rateAppDescription ?? '为我们打分，支持开发',
              trailing: const Icon(Icons.star, size: 20, color: Color(0xFFEB144C)),
              isFocused: state.focusedIndex == focusIndex,
              onTap: onRateTap,
            ),
          ],
        ),
      );
      focusIndex++;
      groupIndex++;
    }

    // 建议和反馈邮箱选项
    options.add(
      Group(
        groupIndex: groupIndex, // 分组 2（中文时）或分组 1（非中文时）
        children: [
          _buildOptionItem(
            context: context,
            focusNode: focusNodes[focusIndex],
            icon: Icons.email,
            title: S.of(context).officialEmail ?? '建议和反馈邮箱',
            subtitle: Config.officialEmail,
            trailing: const Icon(Icons.copy, size: 20, color: Colors.grey),
            isFocused: state.focusedIndex == focusIndex,
            onTap: onEmailTap,
          ),
        ],
      ),
    );
    focusIndex++;
    groupIndex++;

    // 合作联系邮箱（如果需要的话）
    if (Config.algorithmReportEmail != null && onBusinessTap != null) {
      options.add(
        Group(
          groupIndex: groupIndex, // 分组 3（中文时）或分组 2（非中文时）
          children: [
            _buildOptionItem(
              context: context,
              focusNode: focusNodes[focusIndex],
              icon: Icons.report,
              title: S.of(context).algorithmReport ?? '商务合作联系',
              subtitle: Config.algorithmReportEmail!,
              trailing: const Icon(Icons.copy, size: 20, color: Colors.grey),
              isFocused: state.focusedIndex == focusIndex,
              onTap: onBusinessTap!,
            ),
          ],
        ),
      );
    }

    return Column(children: options);
  }

  // 构建选项项
  Widget _buildOptionItem({
    required BuildContext context,
    required FocusNode focusNode,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required bool isFocused,
    required VoidCallback onTap,
  }) {
    const selectedColor = Color(0xFFEB144C);
    const unselectedColor = Color(0xFFDFA02A);
    
    return FocusableItem(
      focusNode: focusNode,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isFocused ? darkenColor(unselectedColor, 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isFocused ? Border.all(color: selectedColor, width: 2) : null,
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
