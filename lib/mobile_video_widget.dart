import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 创建 MobileVideoWidget 组件，用于在移动设备上显示视频内容
class MobileVideoWidget extends StatefulWidget {
  final BetterPlayerController? controller; // 视频播放器控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调方法
  final String? toastString; // 提示信息字符串
  final bool? isLandscape; // 是否为横屏模式
  final Widget drawChild; // 自定义子组件，通常为频道列表或相关界面
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final GestureTapCallback onChangeSubSource; // 数据源变更回调方法
  final Function(String) toggleFavorite; // 收藏操作函数
  final bool Function(String) isChannelFavorite; // 判断频道是否被收藏
  final String currentChannelId; // 当前频道ID
  final String currentChannelLogo; // 当前频道LOGO
  final String currentChannelTitle; // 当前频道名称
  final bool isAudio; // 是否为音频模式
  final AdManager adManager; // AdManager 参数
  // 新增参数，与 TableVideoWidget 保持一致
  final bool showPlayIcon; // 播放图标状态
  final bool showPauseIconFromListener; // 非用户触发的暂停图标状态
  final bool isHls; // 是否为 HLS 流
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // HLS 重试回调

  // 构造函数
  const MobileVideoWidget({
    Key? key,
    required this.controller,
    required this.drawChild,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.onChangeSubSource,
    required this.toggleFavorite,
    required this.isChannelFavorite,
    required this.currentChannelId,
    required this.currentChannelLogo,
    required this.currentChannelTitle,
    required this.adManager,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.isAudio = false,
    this.showPlayIcon = false, // 默认值
    this.showPauseIconFromListener = false, // 默认值
    this.isHls = false, // 默认值
    this.onUserPaused,
    this.onRetry,
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

class _MobileVideoWidgetState extends State<MobileVideoWidget> {
  // AppBar 分割线 - 优化为渐变效果并添加阴影
  static final _appBarDivider = PreferredSize(
    preferredSize: Size.fromHeight(1),
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
            offset: Offset(0, 1),
          ),
        ],
      ),
    ),
  );

  // 抽离logo组件到非静态变量
  late final Widget _appBarLogo;

  // 通用方法：执行导航操作并处理播放暂停和标题栏显示
  Future<void> _executeWithPauseAndNavigation(String routeName, String errorMessage) async {
    LogUtil.safeExecute(() async {
      if (!EnvUtil.isMobile) {
        // 隐藏标题栏（如果不是移动设备）
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }

      final wasPlaying = widget.controller?.isPlaying() ?? false; // 检查播放器当前是否播放中
      if (wasPlaying) {
        widget.controller?.pause(); // 当前播放中，则暂停播放以节省资源
        widget.onUserPaused?.call(); // 通知 LiveHomePage 用户暂停
      }

      await Navigator.of(context).pushNamed(routeName); // 导航至指定页面

      if (wasPlaying) {
        widget.controller?.play(); // 返回时恢复播放
      }

      if (!EnvUtil.isMobile) {
        // 恢复标题栏显示（如果不是移动设备）
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      }
    }, errorMessage); // 记录错误日志
  }

  // 处理“添加”按钮点击事件
  Future<void> _handleAddPressed() async {
    await _executeWithPauseAndNavigation(RouterKeys.subScribe, '执行操作按钮发生错误');
    final m3uData = SpUtil.getString('m3u_cache', defValue: ''); // 返回 String?
    // 检查 M3U 数据是否有效，无效则触发数据源变更
    if (m3uData?.isEmpty ?? true || !isValidM3U(m3uData ?? '')) {
      widget.onChangeSubSource();
    }
  }

  // 处理“设置”按钮点击事件
  Future<void> _handleSettingsPressed() async {
    await _executeWithPauseAndNavigation(RouterKeys.setting, '执行操作设置按钮发生错误');
  }

  // 延迟初始化变量，减少不必要的计算
  late final List<Widget> _appBarIcons;
  late bool _isLandscape; // 修改为非 final，便于在 didChangeDependencies 中初始化
  late final double _playerHeight;
  late final double _finalAspectRatio; // 新增：提前确定 aspectRatio

  @override
  void initState() {
    super.initState();
    // 初始化logo - 添加微妙阴影
    _appBarLogo = Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo-2.png',
        height: 36,
        fit: BoxFit.contain,
      ),
    );

    // 初始化操作按钮列表 - 无动画
    _appBarIcons = [
      // 暂时注释掉用户自己添加播放列表的功能
      // IconButton(
      //   padding: EdgeInsets.zero,
      //   visualDensity: VisualDensity.compact,
      //   icon: const Icon(Icons.add, size: 24, color: Colors.white), // 白色图标
      //   onPressed: _handleAddPressed,
      // ),
      // const SizedBox(width: 8),
      IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.settings_outlined, size: 24, color: Colors.white), // 白色图标
        onPressed: _handleSettingsPressed,
      ),
      const SizedBox(width: 8),
    ];

    // 在 initState 中初始化 aspectRatio，避免 build 中重复计算
    _finalAspectRatio = widget.controller?.videoPlayerController?.value.aspectRatio ?? widget.aspectRatio;
    // 使用 widget.aspectRatio 动态计算高度，并添加边界检查
    _playerHeight = MediaQuery.of(context).size.width / (_finalAspectRatio > 0 ? _finalAspectRatio : 16 / 9);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在 didChangeDependencies 中初始化 _isLandscape，确保 MediaQuery 数据可用
    _isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, // 透明背景以显示渐变
        elevation: 0,
        toolbarHeight: 48.0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: _appBarLogo,
        bottom: _appBarDivider,
        actions: _appBarIcons,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient( // 深灰色渐变
              colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), // 顶部圆角
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black,
            width: double.infinity,
            height: _playerHeight,
            child: TableVideoWidget(
              controller: widget.controller,
              toastString: widget.toastString,
              isLandscape: _isLandscape,
              aspectRatio: _finalAspectRatio, // 使用提前确定的 aspectRatio
              isBuffering: widget.isBuffering,
              isPlaying: widget.isPlaying,
              drawerIsOpen: false,
              toggleFavorite: widget.toggleFavorite,
              isChannelFavorite: widget.isChannelFavorite,
              currentChannelId: widget.currentChannelId,
              currentChannelLogo: widget.currentChannelLogo,
              currentChannelTitle: widget.currentChannelTitle,
              changeChannelSources: widget.changeChannelSources,
              isAudio: widget.isAudio,
              adManager: widget.adManager,
              showPlayIcon: widget.showPlayIcon, // 新增：传递播放图标状态
              showPauseIconFromListener: widget.showPauseIconFromListener, // 新增：传递暂停图标状态
              isHls: widget.isHls, // 新增：传递 HLS 状态
              onUserPaused: widget.onUserPaused, // 新增：用户暂停回调
              onRetry: widget.onRetry, // 新增：HLS 重试回调
            ),
          ),
          Flexible(
            // 如果提示信息为 'UNKNOWN', 显示空页面，并提供刷新回调
            child: widget.toastString == 'UNKNOWN'
                ? EmptyPage(onRefresh: widget.onChangeSubSource)
                : widget.drawChild, // 否则显示传入的自定义子组件
          ),
        ],
      ),
    );
  }

  // 判断 M3U 数据是否有效，增强逻辑以提高准确性
  bool isValidM3U(String data) {
    // 检查是否为空、是否包含 #EXTM3U 标识符，以及是否至少有一个有效条目（如 #EXTINF）
    return data.isNotEmpty && data.contains('#EXTM3U') && data.contains('#EXTINF');
  }
}
