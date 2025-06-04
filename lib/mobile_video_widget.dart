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

// 在移动设备上显示视频内容
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
  final AdManager adManager; // 广告管理实例
  final bool showPlayIcon; // 是否显示播放图标
  final bool showPauseIconFromListener; // 是否显示非用户触发的暂停图标
  final bool isHls; // 是否为 HLS 流
  final VoidCallback? onUserPaused; // 用户暂停时的回调
  final VoidCallback? onRetry; // HLS 重试时的回调

  // 构造函数，定义组件所需的所有参数
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
    this.showPlayIcon = false,
    this.showPauseIconFromListener = false,
    this.isHls = false,
    this.onUserPaused,
    this.onRetry,
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

class _MobileVideoWidgetState extends State<MobileVideoWidget> {
  // 定义 AppBar 分割线，设置为静态常量以复用
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

  // 定义 AppBar 的装饰样式，设置为静态常量以优化性能
  static final _appBarDecoration = BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2), // 保持原始的透明度0.2
        blurRadius: 10,
        spreadRadius: 2,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // 添加常量定义
  static const _aspectRatio = 16.0 / 9.0; // 固定宽高比

  late final Widget _appBarLogo; // 延迟初始化 AppBar 的 Logo 组件

  // 执行导航操作，暂停播放并调整标题栏状态
  Future<void> _executeWithPauseAndNavigation(String routeName, String errorMessage) async {
    LogUtil.safeExecute(() async {
      final wasPlaying = widget.controller?.isPlaying() ?? false; // 获取当前播放状态
      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false); // 隐藏标题栏
      }
      if (wasPlaying) {
        widget.controller?.pause(); // 暂停播放以节省资源
        widget.onUserPaused?.call(); // 通知用户暂停事件
      }
      await Navigator.of(context).pushNamed(routeName); // 导航到指定路由
      if (wasPlaying) {
        widget.controller?.play(); // 返回时恢复播放
      }
      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true); // 恢复标题栏
      }
    }, errorMessage); // 记录异常日志
  }

  // 处理"添加"按钮点击，导航并验证 M3U 数据
  Future<void> _handleAddPressed() async {
    await _executeWithPauseAndNavigation(RouterKeys.subScribe, '执行操作按钮发生错误');
    final m3uData = SpUtil.getString('m3u_cache', defValue: ''); // 获取缓存的 M3U 数据
    if (m3uData?.isEmpty ?? true || !isValidM3U(m3uData ?? '')) {
      widget.onChangeSubSource(); // 数据无效时触发数据源变更
    }
  }

  // 处理"设置"按钮点击，导航至设置页面
  Future<void> _handleSettingsPressed() async {
    await _executeWithPauseAndNavigation(RouterKeys.setting, '执行操作设置按钮发生错误');
  }

  late final List<Widget> _appBarIcons; // 延迟初始化 AppBar 操作按钮列表
  late bool _isLandscape; // 动态跟踪屏幕方向
  double? _playerHeight; // 播放器高度，动态计算

  @override
  void initState() {
    super.initState();
    // 初始化 AppBar Logo，添加阴影效果
    _appBarLogo = Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo-2.png',
        height: 36,
        fit: BoxFit.contain,
      ),
    );

    // 初始化 AppBar 操作按钮
    _appBarIcons = [
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
    // 初始化屏幕方向和播放器高度，确保 MediaQuery 数据可用
    _isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;
    _updatePlayerHeight(); // 更新播放器高度
  }

  // 更新播放器高度，固定为屏幕宽度的 16:9 比例
  void _updatePlayerHeight() {
    final screenWidth = MediaQuery.of(context).size.width;
    _playerHeight = screenWidth / _aspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    // 使用 OrientationBuilder 监听屏幕方向变化
    return OrientationBuilder(
      builder: (context, orientation) {
        _isLandscape = orientation == Orientation.landscape;
        _updatePlayerHeight(); // 更新播放器高度

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent, // 透明背景显示渐变
            elevation: 0,
            toolbarHeight: 48.0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: _appBarLogo,
            bottom: _appBarDivider,
            actions: _appBarIcons,
            flexibleSpace: Container(
              decoration: _appBarDecoration, // 应用静态装饰样式
            ),
          ),
          body: Column(
            children: [
              Container(
                color: Colors.black,
                width: double.infinity,
                height: _playerHeight ?? 0, // 使用动态高度，防止空值
                child: TableVideoWidget(
                  controller: widget.controller,
                  toastString: widget.toastString,
                  isLandscape: _isLandscape,
                  aspectRatio: _aspectRatio, // 使用常量
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
                  showPlayIcon: widget.showPlayIcon,
                  showPauseIconFromListener: widget.showPauseIconFromListener,
                  isHls: widget.isHls,
                  onUserPaused: widget.onUserPaused,
                  onRetry: widget.onRetry,
                ),
              ),
              Flexible(
                // 根据提示信息决定显示空页面或自定义子组件
                child: widget.toastString == 'UNKNOWN'
                    ? EmptyPage(onRefresh: widget.onChangeSubSource)
                    : widget.drawChild,
              ),
            ],
          ),
        );
      },
    );
  }

  // 判断 M3U 数据有效性，需包含 #EXTM3U 和 #EXTINF
  bool isValidM3U(String data) {
    return data.isNotEmpty && data.contains('#EXTM3U') && data.contains('#EXTINF');
  }
}
