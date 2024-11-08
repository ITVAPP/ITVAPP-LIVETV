import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:itvapp_live_tv/widget/volume_brightness_widget.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';
import 'generated/l10n.dart';

class TableVideoWidget extends StatefulWidget {
  final VideoPlayerController? controller; // 视频控制器，用于控制视频播放
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调函数
  final String? toastString; // 显示提示信息的字符串
  final bool isLandscape; // 标识是否为横屏模式
  final bool isBuffering; // 标识是否正在缓冲视频
  final bool isPlaying; // 标识视频是否正在播放
  final double aspectRatio; // 视频的宽高比
  final bool drawerIsOpen; // 标识抽屉菜单是否已打开
  final Function(String) toggleFavorite; // 添加/取消收藏的回调函数
  final bool Function(String) isChannelFavorite; // 判断当前频道是否已收藏
  final String currentChannelId;
  final VoidCallback? onToggleDrawer;

  const TableVideoWidget({
    super.key,
    required this.controller,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.drawerIsOpen,
    required this.toggleFavorite,
    required this.isChannelFavorite,
    required this.currentChannelId,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener {
  // 样式常量
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  bool _isShowMenuBar = true; // 控制是否显示底部菜单栏
  bool _isShowPauseIcon = false; // 控制是否显示暂停图标
  bool _isShowPlayIcon = false; // 新增：控制播放图标显示
  bool _isShowDatePosition = false; // 新增：控制时间显示
  Timer? _pauseIconTimer; // 用于控制暂停图标显示时间的计时器

  // 维护 drawerIsOpen 的本地状态
  bool _drawerIsOpen = false;
  
  // 统一的控制图标样式方法
  Widget _buildControlIcon({
    required IconData icon,
    Color backgroundColor = Colors.black,
    Color iconColor = Colors.white,
    VoidCallback? onTap,
  }) {
    Widget iconWidget = Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor.withOpacity(0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10.0),
        child: Icon(
          icon,
          size: 78,
          color: iconColor.withOpacity(0.85),
        ),
      ),
    );

    // 如果有点击事件,则包装 GestureDetector
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: iconWidget,
      );
    }
    return iconWidget;
  }

  // 新增：处理选择键和确认键的点击事件
  Future<void> _handleSelectPress() async {
    // 1. 如果视频正在播放
    if (widget.isPlaying) {
      // 1.1 如果没有定时器在运行
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 1.11 如果正在播放中，显示暂停图标，并启动一个 3 秒的定时器
        setState(() {
          _isShowPauseIcon = true;
          _isShowPlayIcon = false; // 确保播放图标隐藏
        });
        _pauseIconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isShowPauseIcon = false; // 在定时器结束时，隐藏暂停图标
            });
          }
        });
      } else {
        // 1.2 如果有定时器在运行
        await widget.controller?.pause(); // 暂停视频播放
        _pauseIconTimer?.cancel(); // 取消定时器
        setState(() {
          _isShowPauseIcon = false; // 隐藏暂停图标
          _isShowPlayIcon = true;   // 显示播放图标
        });
      }
    } else {
      // 1.12 如果正在暂停中，隐藏播放图标，播放视频
      await widget.controller?.play();
      setState(() {
        _isShowPlayIcon = false; // 隐藏播放图标
      });
    }

     // 2. 仅在横屏模式下切换时间和菜单栏显示状态
     if (widget.isLandscape) {
       setState(() {
         _isShowDatePosition = !_isShowDatePosition;
         _isShowMenuBar = !_isShowMenuBar;
       });
     }
  }

  // 创建一个私有方法，用于关闭抽屉 (保持不变)
  void _closeDrawerIfOpen() {
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;  // 更新本地状态，确保抽屉关闭
        widget.onToggleDrawer?.call();  // 调用关闭抽屉的回调
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _drawerIsOpen = widget.drawerIsOpen; // 初始状态设置为 widget 传递的值

    // 非移动设备时，注册窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 当父组件的 drawerIsOpen 状态变化时，同步本地 _drawerIsOpen 状态
    if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      setState(() {
        _drawerIsOpen = widget.drawerIsOpen;
      });
    }
  }

  @override
  void dispose() {
    // 非移动设备时，移除窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    _pauseIconTimer?.cancel(); // 取消计时器
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    LogUtil.safeExecute(() {
      // 当进入全屏模式时隐藏标题栏
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    LogUtil.safeExecute(() {
      // 离开全屏时，按横竖屏状态决定是否显示标题栏按钮
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        // 确保移动设备更新屏幕方向
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }, '离开全屏时发生错误');
  }

  @override
  void onWindowResize() {
    LogUtil.safeExecute(() {
      // 调整窗口大小时根据横竖屏状态决定标题栏按钮的显示
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);

      // 在窗口大小变化时关闭抽屉，避免布局错乱
      _closeDrawerIfOpen();  // 调用封装的关闭抽屉方法
    }, '调整窗口大小时发生错误');
  }

  // 收藏按钮的逻辑
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
    return IconButton(
      tooltip: widget.isChannelFavorite(currentChannelId) ? S.current.removeFromFavorites : S.current.addToFavorites,
      padding: showBackground ? null : EdgeInsets.zero, // 竖屏下移除内边距
      constraints: showBackground ? null : const BoxConstraints(), // 竖屏下移除默认大小限制
      style: showBackground
          ? IconButton.styleFrom(
              backgroundColor: _backgroundColor, // 使用提取的背景颜色
              side: _iconBorderSide, // 使用提取的边框样式
            )
          : null,
      icon: Icon(
        widget.isChannelFavorite(currentChannelId) ? Icons.favorite : Icons.favorite_border,
        color: widget.isChannelFavorite(currentChannelId) ? Colors.red : _iconColor,
      ),
      onPressed: () {
        widget.toggleFavorite(currentChannelId); // 切换收藏状态
        setState(() {}); // 刷新UI以更新图标状态
      },
    );
  }

  // 切换频道源按钮的逻辑
  Widget buildChangeChannelSourceButton(bool showBackground) {
    return IconButton(
      tooltip: S.of(context).tipChangeLine, // 提示信息
      padding: showBackground ? null : EdgeInsets.zero, // 竖屏下移除内边距
      constraints: showBackground ? null : const BoxConstraints(), // 竖屏下移除大小限制
      style: showBackground
          ? IconButton.styleFrom(
              backgroundColor: _backgroundColor, // 使用提取的背景颜色
              side: _iconBorderSide, // 使用提取的边框样式
            )
          : null,
      icon: Icon(Icons.legend_toggle, color: _iconColor),
      onPressed: () {
          // 仅在横屏模式下隐藏菜单栏和抽屉
          if (widget.isLandscape) {
              _closeDrawerIfOpen(); 
              setState(() => _isShowMenuBar = false); // 隐藏菜单栏
          }
          widget.changeChannelSources?.call(); // 调用切换频道源的回调函数
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    String currentChannelId = widget.currentChannelId;

    return Stack(
      children: [
        // 视频播放区域
        GestureDetector(
          onTap: _drawerIsOpen ? null : () => _handleSelectPress(),
          onDoubleTap: _drawerIsOpen ? null : () {
            LogUtil.safeExecute(() {
              widget.isPlaying ? widget.controller?.pause() : widget.controller?.play();
            }, '双击播放/暂停发生错误');
          },
          child: Container(
            alignment: Alignment.center,
            color: Colors.black, // 黑色背景
            // 如果视频控制器已初始化，显示视频播放器，否则显示占位背景
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 仅在视频初始化后设置宽高比
                      AspectRatio(
                        aspectRatio: widget.controller!.value.aspectRatio, // 动态获取视频的实际宽高比
                        child: VideoPlayer(widget.controller!),
                      ),
                      // 修改: 如果显示播放图标或视频未播放且抽屉未打开时显示播放按钮
                      if (_isShowPlayIcon || (!widget.isPlaying && !_drawerIsOpen))
                        _buildControlIcon(
                          icon: Icons.play_arrow,
                          onTap: () => _handleSelectPress(),
                        ),
                      // 修改: 显示暂停图标
                      if (_isShowPauseIcon)
                        _buildControlIcon(
                          icon: Icons.pause,
                        ),
                    ],
                  )
                // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                : VideoHoldBg(
                    toastString: _drawerIsOpen ? '' : widget.toastString, // 提示缓冲或加载状态
                    showBingBackground: false, // 可根据需求设置为 true 或 false
                  ),
          ),
        ),
        // 音量和亮度控制组件
        const VolumeBrightnessWidget(),
        // 修改：根据 _isShowDatePosition 控制时间显示
        if (_isShowDatePosition && !_drawerIsOpen)
          const DatePositionWidget(),
        // 横屏模式下的底部菜单栏按钮
        if (widget.isLandscape && !_drawerIsOpen && _isShowMenuBar) ...[
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: _isShowMenuBar ? 20 : -50, // 根据播放状态调整菜单栏的显示/隐藏
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Spacer(),
                  // 频道列表按钮，点击打开抽屉菜单
                  IconButton(
                    tooltip: S.of(context).tipChannelList,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.list_alt, color: _iconColor),
                    onPressed: () {
                      LogUtil.safeExecute(() {
                        setState(() {
                          _isShowMenuBar = false;
                         widget.onToggleDrawer?.call();  // 通过回调打开/关闭抽屉
                        });
                      }, '切换频道发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  // 收藏按钮
                  buildFavoriteButton(currentChannelId, true),
                  const SizedBox(width: 3),
                  // 切换频道源按钮
                  buildChangeChannelSourceButton(true),
                  const SizedBox(width: 3),
                  // 设置按钮，点击进入设置页面
                  IconButton(
                    tooltip: S.of(context).settings,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.settings, color: _iconColor),
                    onPressed: () {
                       _closeDrawerIfOpen(); 
                      LogUtil.safeExecute(() {
                        setState(() => _isShowMenuBar = false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SettingPage()),
                        );
                      }, '进入设置页面发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  // 切换竖屏按钮，调整为竖屏模式
                  IconButton(
                    tooltip: S.of(context).portrait,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.screen_rotation, color: _iconColor),
                    onPressed: () async {
                      LogUtil.safeExecute(() async {
                        if (EnvUtil.isMobile) {
                          // 移动设备设置为竖屏
                          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        } else {
                          // 桌面设备调整窗口大小为竖屏
                          await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                          Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                        }
                      }, '切换为竖屏时发生错误');
                    },
                  ),
                  if (!EnvUtil.isMobile) const SizedBox(width: 6),
                  // 全屏切换按钮，显示或退出全屏
                  if (!EnvUtil.isMobile)
                    IconButton(
                      tooltip: S.of(context).fullScreen,
                      style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                      icon: FutureBuilder<bool>(
                        future: windowManager.isFullScreen(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Icon(
                              snapshot.data! ? Icons.close_fullscreen : Icons.fit_screen_outlined,
                              color: _iconColor,
                            );
                          } else {
                            return Icon(Icons.fit_screen_outlined, color: _iconColor);
                          }
                        },
                      ),
                      onPressed: () async {
                        LogUtil.safeExecute(() async {
                          final isFullScreen = await windowManager.isFullScreen();
                          windowManager.setFullScreen(!isFullScreen); // 切换全屏状态
                        }, '切换为全屏时发生错误');
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
        // 非横屏时右下角的按钮
        if (!widget.isLandscape)
          Positioned(
            right: 8,
            bottom: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 收藏按钮
                buildFavoriteButton(currentChannelId, false),
                // 切换频道源按钮
                buildChangeChannelSourceButton(false),
                // 旋转按钮
                IconButton(
                  tooltip: S.of(context).landscape,
                  padding: EdgeInsets.zero, // 移除内边距
                  constraints: const BoxConstraints(), // 移除默认大小限制
                  onPressed: () async {
                    if (EnvUtil.isMobile) {
                      SystemChrome.setPreferredOrientations(
                          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                      return;
                    }
                    await windowManager.setSize(const Size(800, 800 * 9 / 16), animate: true);
                    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                    Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                  },
                  icon: Icon(Icons.screen_rotation, color: _iconColor),
                ),
              ],
            ),
          )
      ],
    );
  }
}
