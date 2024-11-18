import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'generated/l10n.dart';

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
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.isAudio = false, // 默认为视频模式
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

class _MobileVideoWidgetState extends State<MobileVideoWidget> {
  // 常量定义
  static const _appBarLogo = Padding(
    padding: EdgeInsets.only(left: 4),
    child: Image.asset(
      'assets/images/logo.png',
      height: 28,
      fit: BoxFit.contain,
    ),
  );

  static const _appBarDivider = PreferredSize(
    preferredSize: Size.fromHeight(1),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFF424242),
      ),
      child: SizedBox(height: 0.5),
    ),
  );

  // 抽离回调方法，减少在build函数中重复生成不必要的新闭包
  Future<void> _handleAddPressed() async {
    LogUtil.safeExecute(() async {
      if (!EnvUtil.isMobile) {
        // 隐藏标题栏（如果不是移动设备）
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }

      final wasPlaying = widget.controller?.isPlaying() ?? false; // 检查播放器当前是否播放中
      if (wasPlaying) {
        widget.controller?.pause(); // 当前播放中，则暂停播放以节省资源
      }

      await Navigator.of(context).pushNamed(RouterKeys.subScribe); // 推送至订阅页面

      if (wasPlaying) {
        widget.controller?.play(); // 返回时恢复播放
      }

      final m3uData = SpUtil.getString('m3u_cache', defValue: ''); // 获取缓存中的 m3u 数据
      if (m3uData?.isEmpty ?? true || !isValidM3U(m3uData ?? '')) {
        widget.onChangeSubSource(); // 数据无效则触发数据源变更回调
      }

      if (!EnvUtil.isMobile) {
        // 恢复标题栏显示（如果不是移动设备）
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      }
    }, '执行操作按钮发生错误'); // 错误记录日志
  }

  Future<void> _handleSettingsPressed() async {
    LogUtil.safeExecute(() async {
      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }

      final wasPlaying = widget.controller?.isPlaying() ?? false; // 检查播放器当前是否播放中
      if (wasPlaying) {
        widget.controller?.pause(); // 暂停播放
      }

      await Navigator.of(context).pushNamed(RouterKeys.setting); // 推送至设置页面

      if (wasPlaying) {
        widget.controller?.play(); // 恢复播放
      }

      if (!EnvUtil.isMobile) {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true); // 恢复标题栏
      }
    }, '执行操作设置按钮发生错误'); // 错误记录日志
  }

  // 延迟初始化变量，减少不必要的计算
  late final List<Widget> _appBarIcons;
  late final bool _isLandscape;
  late final double _playerHeight;

  @override
  void initState() {
    super.initState();
    // 在initState中设置需要引用context的值
    _isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;
    _playerHeight = MediaQuery.of(context).size.width / (16 / 9);
    
    // 初始化操作按钮列表
    _appBarIcons = [
      IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add, size: 24),
        onPressed: _handleAddPressed,
      ),
      const SizedBox(width: 8),
      IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.settings_outlined, size: 24),
        onPressed: _handleSettingsPressed,
      ),
      const SizedBox(width: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: 58.0,
        centerTitle: false,
        title: _appBarLogo,
        bottom: _appBarDivider,
        actions: _appBarIcons,
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
              aspectRatio: widget.controller?.videoPlayerController?.value.aspectRatio ?? widget.aspectRatio,
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

  // 判断 m3u 数据是否有效，检查其是否包含 M3U 文件必要的标识符
  bool isValidM3U(String data) {
    return data.contains('#EXTM3U');
  }
}
