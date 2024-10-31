import 'dart:async';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sp_util/sp_util.dart';
import 'package:video_player/video_player.dart';

import '../channel_drawer_page.dart';
import '../gradient_progress_bar.dart';
import '../entity/playlist_model.dart';
import '../util/log_util.dart';
import '../util/custom_snackbar.dart';
import '../generated/l10n.dart';

class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap; // 视频播放列表模型，改为三层结构
  final PlayModel? playModel; // 当前播放的频道模型
  final Function(PlayModel? newModel)? onTapChannel; // 点击频道时调用的回调函数

  final VideoPlayerController? controller; // 视频播放器控制器
  final Future<void> Function()? changeChannelSources; // 频道源切换函数
  final GestureTapCallback? onChangeSubSource; // 视频源切换的回调函数
  final String? toastString; // 显示提示信息的字符串
  final bool isLandscape; // 是否横屏显示
  final bool isBuffering; // 视频是否在缓冲
  final bool isPlaying; // 视频是否正在播放
  final double aspectRatio; // 视频显示的宽高比

  const TvPage({
    super.key,
    this.videoMap,
    this.onTapChannel,
    this.controller,
    this.playModel,
    this.changeChannelSources,
    this.onChangeSubSource,
    this.toastString,
    this.isLandscape = false,
    this.isBuffering = false,
    this.isPlaying = false,
    this.aspectRatio = 16 / 9, // 默认宽高比 16:9
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  bool _drawerIsOpen = false; // 侧边抽屉是否打开
  bool _isShowPauseIcon = false; // 是否显示暂停图标
  Timer? _pauseIconTimer; // 暂停图标显示的计时器
  bool _isDatePositionVisible = false; // 控制 DatePositionWidget 显示隐藏
  bool _isError = false; // 标识是否播放过程中发生错误

  // 打开添加源的设置页面
  Future<bool?> _opensetting() async {
    try {
      return Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return const TvSettingPage(); // 进入设置页面
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            var begin = const Offset(0.0, -1.0); // 动画起点为屏幕外顶部
            var end = Offset.zero; // 动画终点为屏幕中间
            var curve = Curves.ease; // 使用缓动曲线

            // 定义位移动画
            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return SlideTransition(
              position: animation.drive(tween), // 应用动画
              child: child,
            );
          },
        ),
      );
    } catch (e, stackTrace) {
      LogUtil.logError('打开添加源设置页面时发生错误', e, stackTrace); // 捕获并记录页面打开时的错误
      return null;
    }
  }

  // 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (!Navigator.canPop(context)) {
      // 如果没有可以返回的页面，显示退出确认对话框
      return await ShowExitConfirm.ExitConfirm(context);
    }

    // 否则，正常返回
    Navigator.pop(context);
    return false; // 不阻止返回
  }

  // 处理选择键逻辑
  Future<void> _handleSelectPress() async {
    // 合并状态更新以减少重绘
    setState(() {
      _isDatePositionVisible = !_isDatePositionVisible;
      _isShowPauseIcon = widget.isPlaying;
    });

    // 启动计时器控制暂停图标显示时间
    if (widget.isPlaying) {
      _pauseIconTimer?.cancel();
      _pauseIconTimer = Timer(const Duration(seconds: 2), () {
        setState(() {
          _isShowPauseIcon = false; // 2秒后隐藏暂停图标
        });
      });
    } else {
      // 播放视频并确保暂停图标不显示
      widget.controller?.play();
      setState(() {
        _isShowPauseIcon = false;
      });
    }
  }

  // 处理键盘事件的函数，处理遥控器输入
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled; // 只处理按键释放事件

    if (_drawerIsOpen) {
      return KeyEventResult.handled; // 阻止方向键在抽屉打开时响应全局事件
    }

    // 根据按键的不同逻辑键值执行相应的操作
    switch (e.logicalKey) {
      case LogicalKeyboardKey.contextMenu:  // 处理菜单键
      case LogicalKeyboardKey.arrowRight:  // 处理右键
        setState(() {
          _drawerIsOpen = true; // 打开侧边抽屉菜单
        });
        break;
      case LogicalKeyboardKey.arrowLeft: 
        break;
      case LogicalKeyboardKey.arrowUp: 
        await widget.changeChannelSources?.call(); // 切换视频源
        break;
      case LogicalKeyboardKey.arrowDown:   
        widget.controller?.pause(); // 暂停视频播放	
        _opensetting(); // 打开设置页面
        break;
      case LogicalKeyboardKey.select:    // 处理选择键
      case LogicalKeyboardKey.enter: // 处理 Enter 键
        _handleSelectPress(); // 调用处理逻辑
        break;  
      case LogicalKeyboardKey.goBack:
        _handleBackPress(context); // 修改的返回键逻辑
        break;
      case LogicalKeyboardKey.audioVolumeUp:
        // 处理音量加键操作
        break;
      case LogicalKeyboardKey.audioVolumeDown:
        // 处理音量减键操作
        break;
      case LogicalKeyboardKey.f5:
        // 处理语音键操作
        break;
      default:
        break;
    }
    return KeyEventResult.handled;  // 返回 KeyEventResult.handled
  }

  // 处理 EPGList 节目点击事件，确保点击后抽屉关闭
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    widget.onTapChannel?.call(selectedProgram); // 切换到选中的节目
    setState(() {
      _drawerIsOpen = false; // 点击节目后关闭抽屉
    });
  }

  @override
  void dispose() {
    try {
      _pauseIconTimer?.cancel();
    } catch (e) {
      LogUtil.logError('释放 _pauseIconTimer 失败', e);
    }
    try {
      widget.controller?.dispose();
    } catch (e) {
      LogUtil.logError('释放 controller 失败', e);
    }
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return WillPopScope(
    onWillPop: () => _handleBackPress(context), // 确保在退出前调用
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Builder(builder: (context) {
        return KeyboardListener(
          focusNode: FocusNode(),  
          onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e), // 处理键盘事件
          child: Container(
            alignment: Alignment.center,
            color: Colors.black,
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    children: [
                      // 显示视频播放器
                      AspectRatio(
                        aspectRatio: widget.controller!.value.aspectRatio,
                        child: SizedBox(
                          width: double.infinity,
                          child: VideoPlayer(widget.controller!),
                        ),
                      ),

                      // 仅在视频暂停时显示播放图标
                      if (!widget.controller!.value.isPlaying)
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.5),
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
                              Icons.play_arrow,
                              size: 78,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ),

                      if (_isDatePositionVisible) const DatePositionWidget(),

                      if ((widget.isBuffering || _isError) && !_drawerIsOpen)
                        _buildBufferingIndicator(),

                      // EPG抽屉显示
                      if (_drawerIsOpen) 
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: ChannelDrawerPage(
                            videoMap: widget.videoMap,
                            playModel: widget.playModel,
                            isLandscape: true,
                          ),
                        ),
                    ],
                  )
                // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                : VideoHoldBg(
                    toastString: _drawerIsOpen ? '' : widget.toastString,
                    videoController: VideoPlayerController.network(''),
                  ),
          ),
        );
      }),
    ),
  );
}

  Widget _buildBufferingIndicator() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(
              width: MediaQuery.of(context).size.width * 0.3,
              height: 5,
            ),
            const SizedBox(height: 8),
            _buildToast(S.of(context).loading),
          ],
        ),
      ),
    );
  }

  Widget _buildToast(String message) {
    return Text(
      message,
      style: TextStyle(color: Colors.white, fontSize: 18),
    );
  }
}
