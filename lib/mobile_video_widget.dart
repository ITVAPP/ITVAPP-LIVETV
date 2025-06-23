import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:iapp_player/iapp_player.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/common_widgets.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 显示移动端视频内容
class MobileVideoWidget extends StatefulWidget {
  final IAppPlayerController? controller; // 视频播放控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源回调
  final String? toastString; // 提示信息
  final bool? isLandscape; // 是否横屏
  final Widget drawChild; // 自定义子组件
  final bool isBuffering; // 是否缓冲中
  final bool isPlaying; // 是否播放中
  final double aspectRatio; // 视频宽高比
  final GestureTapCallback onChangeSubSource; // 数据源变更回调
  final Function(String) toggleFavorite; // 切换收藏状态
  final bool Function(String) isChannelFavorite; // 判断频道是否收藏
  final String currentChannelId; // 当前频道ID
  final String currentChannelLogo; // 当前频道LOGO
  final String currentChannelTitle; // 当前频道名称
  final bool isAudio; // 是否音频模式
  final AdManager adManager; // 广告管理实例
  final bool showPlayIcon; // 是否显示播放图标
  final bool showPauseIconFromListener; // 是否显示非用户暂停图标
  final bool isHls; // 是否HLS流
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // HLS重试回调

  // 初始化视频播放组件及参数
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
  // 定义固定宽高比
  static const _aspectRatio = 16.0 / 9.0;

  late final Widget _appBarLogo; // AppBar Logo组件

  // 执行暂停与导航操作
  Future<void> _executeWithPauseAndNavigation(String routeName, String errorMessage) async {
    LogUtil.safeExecute(() async {
      final wasPlaying = widget.controller?.isPlaying() ?? false; // 检查视频播放状态
      
      if (wasPlaying) {
        widget.controller?.pause(); // 暂停视频
        widget.onUserPaused?.call(); // 触发用户暂停回调
      }
      
      await Navigator.of(context).pushNamed(routeName); // 导航至指定路由
      
      if (wasPlaying) {
        widget.controller?.play(); // 恢复视频播放
      }
    }, errorMessage); // 错误：记录导航或暂停异常
  }

  // 处理设置按钮点击，导航至设置页面
  Future<void> _handleSettingsPressed() async {
    await _executeWithPauseAndNavigation(RouterKeys.setting, '错误：设置按钮操作失败');
  }

  late final List<Widget> _appBarIcons;
  late bool _isLandscape; // 屏幕方向状态
  double? _playerHeight; // 播放器高度

  @override
  void initState() {
    super.initState();
    // 初始化AppBar Logo
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

    // 初始化AppBar操作按钮
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
    // 初始化屏幕方向与播放器高度
    _isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;
    _updatePlayerHeight(); // 更新播放器高度
  }

  // 计算播放器高度，保持16:9比例
  void _updatePlayerHeight() {
    final screenWidth = MediaQuery.of(context).size.width;
    _playerHeight = screenWidth / _aspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    // 监听屏幕方向变化
    return OrientationBuilder(
      builder: (context, orientation) {
        _isLandscape = orientation == Orientation.landscape;
        _updatePlayerHeight(); // 更新播放器高度

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 48.0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: _appBarLogo,
            bottom: const CommonAppBarDivider(),
            actions: _appBarIcons,
            flexibleSpace: Container(
              decoration: const CommonAppBarDecoration(),
            ),
          ),
          body: Column(
            children: [
              Container(
                color: Colors.black,
                width: double.infinity,
                height: _playerHeight ?? 0,
                child: TableVideoWidget(
                  controller: widget.controller,
                  toastString: widget.toastString,
                  isLandscape: _isLandscape,
                  aspectRatio: _aspectRatio,
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
                // 根据提示信息显示空页面或子组件
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

  // 验证M3U数据有效性
  bool isValidM3U(String data) {
    return data.isNotEmpty && data.contains('#EXTM3U') && data.contains('#EXTINF');
  }
}
