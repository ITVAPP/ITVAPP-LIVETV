import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/setting/about_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/widget/remote_control_help.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 电视设置主页面，管理左侧菜单和右侧内容显示
class TvSettingPage extends StatefulWidget {
  const TvSettingPage({super.key});

  @override
  State<TvSettingPage> createState() => TvSettingPageState();
}

class TvSettingPageState extends State<TvSettingPage> {
  // 定义标题样式为静态常量，统一文本格式
  static const _titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  int selectedIndex = 0; // 当前高亮的菜单索引
  int _confirmedIndex = 0; // 用户确认后显示的页面索引
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 缓存最新版本信息

  final List<FocusNode> focusNodes = _generateFocusNodes(5); // 生成5个焦点节点，0为返回按钮，1-4为菜单项

  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景色（红色）
  final Color focusedColor = const Color(0xFFDFA02A); // 聚焦时的背景色（黄色）

  // 生成指定数量的焦点节点列表
  static List<FocusNode> _generateFocusNodes(int count) {
    return List.generate(count, (index) {
      final node = FocusNode();
      return node;
    });
  }

  @override
  void initState() {
    super.initState();
    // 初始化时为每个焦点节点添加监听器，跟踪焦点变化
    for (var node in focusNodes) {
      node.addListener(_handleFocusChange);
    }
  }

  // 处理焦点变化，更新高亮菜单索引
  void _handleFocusChange() {
    final focusedIndex = focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1 && focusedIndex > 0) { // 排除返回按钮（索引0）
      setState(() {
        selectedIndex = focusedIndex - 1; // 调整索引与菜单项对齐
      });
    }
  }

  @override
  void dispose() {
    _disposeFocusNodes(focusNodes); // 清理所有焦点节点
    super.dispose();
  }

  // 统一销毁焦点节点，移除监听并释放资源
  void _disposeFocusNodes(List<FocusNode> focusNodes) {
    for (var focusNode in focusNodes) {
      focusNode.removeListener(_handleFocusChange); // 移除焦点变化监听
      focusNode.dispose();
    }
  }

  // 检查版本更新并显示结果提示
  Future<void> _checkForUpdates() async {
    try {
      await CheckVersionUtil.checkVersion(context, true, true, true); // 执行版本检查
      setState(() {
        _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 更新版本信息
      });

      // 根据版本检查结果显示提示
      if (_latestVersionEntity != null) {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).newVersion(_latestVersionEntity!.latestVersion!), // 显示新版本号
          duration: Duration(seconds: 4),
        );
      } else {
        CustomSnackBar.showSnackBar(
          context,
          S.of(context).latestVersion, // 提示已是最新版本
          duration: Duration(seconds: 4),
        );
      }
    } catch (e) {
      LogUtil.e('Error checking for updates: $e'); // 记录版本检查错误日志
      CustomSnackBar.showSnackBar(
        context,
        S.of(context).netReceiveTimeout, // 提示网络超时
        duration: Duration(seconds: 4),
      );
    }
  }

  // 构建通用菜单项，支持焦点和选中状态
  Widget buildListTile({
    required IconData icon,
    required String title,
    required int index,
    required VoidCallback onTap,
  }) {
    final bool isSelected = _confirmedIndex == index; // 判断是否为确认选中项
    final bool hasFocus = focusNodes[index + 1].hasFocus; // 判断是否聚焦

    return FocusableItem(
      focusNode: focusNodes[index + 1], // 绑定对应焦点节点（从1开始）
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.white,
        ), // 菜单项图标
        title: Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 选中时加粗
            color: Colors.white,
          ),
        ), // 菜单项标题
        selected: isSelected, // 设置选中状态
        tileColor: hasFocus ? focusedColor : (isSelected ? selectedColor : Colors.transparent), // 动态设置背景色
        onTap: () {
          if (selectedIndex != index) {
            setState(() {
              selectedIndex = index; // 更新高亮索引
              _confirmedIndex = index; // 更新确认索引
            });
          }
          onTap(); // 执行点击回调
        },
      ),
    );
  }

  // 根据确认索引动态构建右侧内容页面
  Widget _buildRightPanel() {
    switch (_confirmedIndex) {
      case 0:
        return const AboutPage(); // 显示关于我们页面
      case 1:
        return const SettingFontPage(); // 显示字体设置页面
      case 2:
        return SettinglogPage(); // 显示日志页面
      case 3:
      case 4:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png', // 显示应用Logo
                width: 98,
                height: 98,
              ),
              const SizedBox(height: 18),
              Text(
                S.of(context).checkUpdate, // 显示"检查更新"文本
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      default:
        return Container(); // 默认返回空容器，避免索引错误
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: TvKeyNavigation(
        focusNodes: focusNodes, // 绑定焦点节点列表
        cacheName: 'TvSettingPage', // 设置页面缓存名称
        initialIndex: selectedIndex + 1, // 初始焦点索引
        isFrame: true, // 启用框架导航模式
        frameType: "parent", // 设置为父级框架
        isVerticalGroup: true, // 启用垂直分组导航
        child: Row(
          children: [
            // 左侧菜单区域
            SizedBox(
              width: 228, // 固定菜单宽度
              child: Group(
                groupIndex: 0, // 菜单分组索引
                child: Scaffold(
                  appBar: AppBar(
                    leading: FocusableItem(
                      focusNode: focusNodes[0], // 返回按钮焦点节点
                      child: ListTile(
                        leading: Icon(
                          Icons.arrow_back,
                          color: focusNodes[0].hasFocus ? focusedColor : Colors.white, // 焦点时变黄色
                        ),
                        onTap: () {
                          Navigator.of(context).pop(); // 点击返回上一页
                        },
                      ),
                    ),
                    title: Consumer<LanguageProvider>(
                      builder: (context, languageProvider, child) {
                        return Text(
                          S.of(context).settings, // 显示"设置"标题
                          style: _titleStyle,
                        );
                      },
                    ),
                  ),
                  body: Column(
                    children: [
                      buildListTile(
                        icon: Icons.info_outline,
                        title: S.of(context).aboutApp, // "关于我们"菜单项
                        index: 0,
                        onTap: () {
                          setState(() {
                            selectedIndex = 0;
                            _confirmedIndex = 0;
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.font_download,
                        title: S.of(context).fontTitle, // "字体"菜单项
                        index: 1,
                        onTap: () {
                          setState(() {
                            selectedIndex = 1;
                            _confirmedIndex = 1;
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.view_list,
                        title: S.of(context).slogTitle, // "日志"菜单项
                        index: 2,
                        onTap: () {
                          setState(() {
                            selectedIndex = 2;
                            _confirmedIndex = 2;
                          });
                        },
                      ),
                      buildListTile(
                        icon: Icons.system_update,
                        title: S.of(context).updateTitle, // "更新"菜单项
                        index: 3,
                        onTap: () {
                          setState(() {
                            selectedIndex = 3;
                            _confirmedIndex = 3;
                          });
                          _checkForUpdates(); // 检查版本更新
                        },
                      ),
                      buildListTile(
                        icon: Icons.system_update,
                        title: S.of(context).remotehelp, // "帮助"菜单项
                        index: 4,
                        onTap: () {
                          setState(() {
                            selectedIndex = 4;
                            _confirmedIndex = 4;
                          });
                          Future.microtask(() async {
                            await RemoteControlHelp.show(context); // 显示遥控帮助界面
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 右侧内容区域
            Expanded(
              child: _buildRightPanel(), // 动态显示右侧页面
            ),
          ],
        ),
      ),
    );
  }
}
