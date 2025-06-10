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
import 'package:itvapp_live_tv/setting/agreement_page.dart';
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

  int selectedIndex = 0; // 当前焦点所在的菜单索引（仅用于高亮显示）
  int _confirmedIndex = 0; // 用户确认后显示的页面索引（用于决定显示哪个页面）
  VersionEntity? _latestVersionEntity = CheckVersionUtil.latestVersionEntity; // 缓存最新版本信息

  // 根据debugMode动态生成焦点节点，日志在最后时需要7个节点（包含返回按钮）
  late final List<FocusNode> focusNodes = _generateFocusNodes(LogUtil.debugMode ? 7 : 6);

  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景色（红色）
  final Color focusedColor = const Color(0xFFDFA02A); // 聚焦时的背景色（黄色）

  // 用于跟踪当前页面实例，避免重复创建
  Widget? _currentPage;
  int? _currentPageIndex;

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
    // 为每个焦点节点添加监听器，但只更新selectedIndex
    for (int i = 0; i < focusNodes.length; i++) {
      final index = i;
      focusNodes[i].addListener(() {
        if (focusNodes[index].hasFocus && mounted) {
          // 焦点变化时只更新selectedIndex，不改变_confirmedIndex
          if (index > 0 && selectedIndex != index - 1) {
            setState(() {
              selectedIndex = index - 1;
            });
            LogUtil.i('[TvSettingPage] 焦点移动到: selectedIndex=$selectedIndex');
          }
        }
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
    final bool isConfirmed = _confirmedIndex == index; // 是否为已确认的页面
    final bool isFocused = selectedIndex == index; // 是否为当前焦点
    final bool hasFocus = focusNodes[index + 1].hasFocus; // 实际焦点状态

    // 根据状态决定背景色
    Color? tileColor;
    if (hasFocus) {
      tileColor = focusedColor; // 实际聚焦时显示黄色
    } else if (isConfirmed) {
      tileColor = selectedColor; // 已确认选中时显示红色
    } else {
      tileColor = Colors.transparent; // 默认透明
    }

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
            fontWeight: isConfirmed ? FontWeight.bold : FontWeight.normal, // 确认选中时加粗
            color: Colors.white,
          ),
        ), // 菜单项标题
        tileColor: tileColor, // 使用计算后的背景色
        onTap: () {
          LogUtil.i('[TvSettingPage] 菜单项点击: index=$index, title=$title');
          // 只有当确认索引改变时才更新页面
          if (_confirmedIndex != index) {
            setState(() {
              _confirmedIndex = index; // 更新确认索引
              _currentPage = null; // 清除缓存，强制重新创建页面
              _currentPageIndex = null;
            });
            LogUtil.i('[TvSettingPage] 确认选择: _confirmedIndex=$_confirmedIndex');
          }
          onTap(); // 执行额外的点击回调
        },
      ),
    );
  }

  // 根据确认索引动态构建右侧内容页面
  Widget _buildRightPanel() {
    // 如果当前页面索引没有改变，返回缓存的页面
    if (_currentPageIndex == _confirmedIndex && _currentPage != null) {
      LogUtil.i('[TvSettingPage] 使用缓存页面: _confirmedIndex=$_confirmedIndex');
      return _currentPage!;
    }

    LogUtil.i('[TvSettingPage] _buildRightPanel 创建新页面: _confirmedIndex=$_confirmedIndex');
    
    Widget result;
    switch (_confirmedIndex) {
      case 0:
        LogUtil.i('[TvSettingPage] 创建 AboutPage');
        result = const AboutPage(); // 显示关于我们页面
        break;
      case 1:
        LogUtil.i('[TvSettingPage] 创建 AgreementPage');
        result = const AgreementPage(); // 显示用户协议页面
        break;
      case 2:
        LogUtil.i('[TvSettingPage] 创建 SettingFontPage');
        result = const SettingFontPage(); // 显示字体设置页面
        break;
      case 3:
      case 4:
        LogUtil.i('[TvSettingPage] 显示更新/帮助界面');
        result = Center(
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
        break;
      case 5:
        LogUtil.i('[TvSettingPage] 创建 SettinglogPage');
        result = SettinglogPage(); // 显示日志页面
        break;
      default:
        LogUtil.i('[TvSettingPage] 默认返回空容器');
        result = Container(); // 默认返回空容器，避免索引错误
    }
    
    // 缓存当前页面
    _currentPage = result;
    _currentPageIndex = _confirmedIndex;
    
    LogUtil.i('[TvSettingPage] _buildRightPanel 返回 ${result.runtimeType}');
    return result;
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
                        onTap: () {},
                      ),
                      buildListTile(
                        icon: Icons.description,
                        title: S.of(context).userAgreement, // "用户协议"菜单项
                        index: 1,
                        onTap: () {},
                      ),
                      buildListTile(
                        icon: Icons.font_download,
                        title: S.of(context).fontTitle, // "字体"菜单项
                        index: 2,
                        onTap: () {},
                      ),
                      buildListTile(
                        icon: Icons.system_update,
                        title: S.of(context).updateTitle, // "更新"菜单项
                        index: 3,
                        onTap: () {
                          _checkForUpdates(); // 检查版本更新
                        },
                      ),
                      buildListTile(
                        icon: Icons.system_update,
                        title: S.of(context).remotehelp, // "帮助"菜单项
                        index: 4,
                        onTap: () {
                          Future.microtask(() async {
                            await RemoteControlHelp.show(context); // 显示遥控帮助界面
                          });
                        },
                      ),
                      // 日志选项，仅在debugMode为true时显示
                      if (LogUtil.debugMode)
                        buildListTile(
                          icon: Icons.view_list,
                          title: S.of(context).slogTitle, // "日志"菜单项
                          index: 5,
                          onTap: () {},
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
