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
  final AdManager adManager; // 广告管理器

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
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

class _MobileVideoWidgetState extends State<MobileVideoWidget> {
  // AppBar 分割线，使用渐变效果和阴影
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

  late final Widget _appBarLogo; // AppBar 中的 Logo 组件
  late final List<Widget> _appBarIcons; // AppBar 中的操作按钮列表
  late double _playerHeight; // 播放器高度
  late bool _isLandscape; // 是否为横屏模式
  late double _cachedAspectRatio; // 缓存的视频宽高比

  @override
  void initState() {
    super.initState();
    // 初始化静态变量
    _isLandscape = widget.isLandscape ?? true;
    _cachedAspectRatio = widget.aspectRatio;

    // 初始化 Logo，添加阴影效果
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

    // 初始化操作按钮列表
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
        icon: const Icon(Icons.settings_outlined, size: 24, color: Colors.white),
        onPressed: _handleSettingsPressed,
      ),
      const SizedBox(width: 8),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 计算播放器高度，确保适配不同设备
    final screenWidth = MediaQuery.of(context).size.width;
    _playerHeight = screenWidth / (EnvUtil.isMobile ? (16 / 9) : (21 / 9));
    _isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  void didUpdateWidget(covariant MobileVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当控制器更新时，更新缓存的宽高比
    if (oldWidget.controller != widget.controller) {
      _cachedAspectRatio = widget.controller?.videoPlayerController?.value.aspectRatio ?? widget.aspectRatio;
    }
  }

  // 处理导航的公共方法
  Future<void> _handleNavigation(String route, VoidCallback onComplete) async {
    LogUtil.safeExecute(() async {
      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }

      final wasPlaying = widget.controller?.isPlaying() ?? false;
      if (wasPlaying) {
        widget.controller?.pause();
      }

      await Navigator.of(context).pushNamed(route);

      if (wasPlaying) {
        widget.controller?.play();
      }

      onComplete();

      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      }
    }, '执行导航操作发生错误');
  }

  // 处理添加按钮点击事件
  Future<void> _handleAddPressed() async {
    await _handleNavigation(RouterKeys.subScribe, () {
      final m3uData = SpUtil.getString('m3u_cache', defValue: '');
      if (m3uData.isEmpty || !isValidM3U(m3uData)) {
        widget.onChangeSubSource();
      }
    });
  }

  // 处理设置按钮点击事件
  Future<void> _handleSettingsPressed() async {
    await _handleNavigation(RouterKeys.setting, () {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48.0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: _appBarLogo,
        bottom: _appBarDivider,
        actions: _appBarIcons,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
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
              aspectRatio: _cachedAspectRatio,
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
            ),
          ),
          Flexible(
            child: widget.toastString == 'UNKNOWN'
                ? EmptyPage(onRefresh: widget.onChangeSubSource)
                : widget.drawChild,
          ),
        ],
      ),
    );
  }

  // 判断 M3U 数据是否有效
  bool isValidM3U(String data) {
    return data.contains('#EXTM3U');
  }
}
