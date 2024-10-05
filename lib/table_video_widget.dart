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
  Timer? _pauseIconTimer; // 用于控制暂停图标显示时间的计时器

  // 维护 drawerIsOpen 的本地状态
  bool _drawerIsOpen = false;

  // 创建一个私有方法，用于关闭抽屉
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
        LogUtil.safeExecute(() {
          // 仅在横屏模式下隐藏菜单栏和抽屉
          if (widget.isLandscape) {
              _closeDrawerIfOpen(); 
              setState(() => _isShowMenuBar = false); // 隐藏菜单栏
          }
          widget.changeChannelSources?.call(); // 调用切换频道源的回调函数
        }, '切换频道源按钮发生错误');
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
          onTap: () {
          	
           // 仅在横屏模式下操作
            if (widget.isLandscape) {
              _closeDrawerIfOpen(); 
            setState(() {
              _isShowMenuBar = !_isShowMenuBar; // 切换菜单栏显示/隐藏状态
            });
            }
            
            // 如果视频已暂停，单击继续播放视频
            if (!widget.isPlaying) {
              widget.controller?.play();
            } else {
              if (_isShowPauseIcon) {
                // 如果暂停图标已显示，则暂停视频
                widget.controller?.pause();
                _pauseIconTimer?.cancel(); // 取消计时器
                setState(() {
                  _isShowPauseIcon = false;
                });
              } else {
                // 显示暂停图标并启动计时器
                setState(() {
                  _isShowPauseIcon = true;
                });
                _pauseIconTimer?.cancel(); // 取消之前的计时器
                _pauseIconTimer = Timer(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _isShowPauseIcon = false;
                    });
                  }
                });
              }
            }
          },
          // 双击播放/暂停视频
          onDoubleTap: () {
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
                      // 如果视频未播放且抽屉未打开，显示播放按钮
                      if (!widget.isPlaying)
                        GestureDetector(
                          onTap: () {
                            LogUtil.safeExecute(() => widget.controller?.play(), '显示播放按钮发生错误');
                          },
                          child: Opacity(
                            opacity: 0.5, // 设置透明度
                            child: Icon(Icons.play_circle_outline, color: _iconColor, size: 88),
                          ),
                        ),
                      // 显示暂停图标
                      if (_isShowPauseIcon)
                        Opacity(
                          opacity: 0.5, // 设置透明度
                          child: Icon(Icons.pause_circle_outline, color: _iconColor, size: 88),
                        ),
                    ],
                  )
                // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                : VideoHoldBg(
                    videoController: widget.controller ?? VideoPlayerController.network(''),
                    toastString: _drawerIsOpen ? '' : widget.toastString, // 提示缓冲或加载状态
                  ),
          ),
        ),
        // 音量和亮度控制组件
        const VolumeBrightnessWidget(),
        // 横屏模式下的底部菜单栏按钮
        if (widget.isLandscape && !_drawerIsOpen && _isShowMenuBar) ...[
          const DatePositionWidget(), // 显示时间和日期的组件
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
        // 非横屏时右下角的旋转按钮和收藏按钮
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
