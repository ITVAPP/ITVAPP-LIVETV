import 'dart:async';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:sp_util/sp_util.dart';
import 'package:video_player/video_player.dart';

import '../channel_drawer_page.dart';
import '../entity/playlist_model.dart';
import '../util/log_util.dart';
import '../widget/video_hold_bg.dart';
import '../generated/l10n.dart';

class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap; // 视频播放列表模型
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
  final _videoNode = FocusNode(); // 用于管理键盘焦点的节点
  bool _debounce = true; // 防止按键被快速多次触发
  Timer? _timer; // 定时器用于处理按键节流
  bool _drawerIsOpen = false; // 侧边抽屉是否打开

  bool _isError = false; // 标识是否播放过程中发生错误

  // 防抖处理函数，将操作包装在防抖逻辑中，防止短时间内多次触发相同事件
  void _handleDebounce(Function action, [Duration delay = const Duration(milliseconds: 300)]) {
    if (_debounce) {
      _debounce = false;
      action();  // 执行动作
      _timer = Timer(delay, () {
        _debounce = true;  // 设定一个定时器，在指定时间后恢复防抖开关
        _timer?.cancel();
        _timer = null;
      });
    }
  }

  // 显示错误信息并记录日志
  void _showError(String message) {
    setState(() {
      _isError = true; // 设置错误状态，用于控制UI显示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)), // 显示错误提示
      );

      // 捕获当前堆栈信息并传递给 logError
      try {
        throw Exception(message);
      } catch (e, stackTrace) {
        LogUtil.logError('播放错误：$message', e, stackTrace); // 记录错误日志
      }
    });
  }

  // 打开添加源的设置页面
  Future<bool?> _openAddSource() async {
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

  // 处理键盘事件的函数，处理遥控器输入
  Future<void> _focusEventHandle(BuildContext context, KeyEvent e) async {
    _handleDebounce(() async {
      if (e is! KeyUpEvent) return; // 只处理按键释放事件

      // 根据按键的不同逻辑键值执行相应的操作
      switch (e.logicalKey) {
        case LogicalKeyboardKey.arrowRight:
          // 处理右键操作
          break;
        case LogicalKeyboardKey.arrowLeft:
          // 处理左键操作
          break;
        case LogicalKeyboardKey.arrowUp:
          _videoNode.unfocus(); // 移除视频区域的焦点
          await widget.changeChannelSources?.call(); // 切换视频源
          _restoreFocus(); // 延迟恢复焦点
          break;
        case LogicalKeyboardKey.arrowDown:
          widget.controller?.pause(); // 暂停视频播放
          _videoNode.unfocus(); // 移除焦点
          await _openAddSource(); // 打开设置页面以添加新的视频源
          final m3uData = SpUtil.getString('m3u_cache', defValue: '')!;
          if (m3uData == '') {
            widget.onChangeSubSource?.call(); // 如果没有视频源，调用切换回调
          } else {
            widget.controller?.play(); // 如果有视频源，恢复视频播放
          }
          _restoreFocus(); // 延迟恢复焦点
          break;
        case LogicalKeyboardKey.select:
          if (_isError) {
            _showError('视频加载失败，请重试'); // 如果播放出错，显示提示信息
            return;
          }

          if (widget.controller?.value.isInitialized == true &&
              !widget.controller!.value.isPlaying &&
              !widget.controller!.value.isBuffering) {
            widget.controller?.play(); // 如果视频未播放且未缓冲，则开始播放
          } else {
            if (!Scaffold.of(context).isDrawerOpen) {
              Scaffold.of(context).openDrawer(); // 打开频道列表的侧边抽屉
            }
          }
          break;
        case LogicalKeyboardKey.goBack:
          Navigator.pop(context); // 返回上一个页面
          break;
        case LogicalKeyboardKey.contextMenu:
          if (!Scaffold.of(context).isDrawerOpen) {
            Scaffold.of(context).openDrawer(); // 打开侧边抽屉菜单
          }
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
    });
  }

  // 恢复焦点的方法，封装了延迟操作，以便在适当的时间恢复键盘焦点
  void _restoreFocus([Duration delay = const Duration(milliseconds: 100)]) {
    Future.delayed(delay, () => _videoNode.requestFocus());
  }

  // 抽屉状态处理，当抽屉打开或关闭时触发相应的焦点管理
  void _handleDrawerChange(bool isOpen) {
    LogUtil.safeExecute(() {
      setState(() {
        _drawerIsOpen = isOpen; // 记录当前抽屉状态
        if (_drawerIsOpen) {
          _videoNode.unfocus(); // 如果抽屉打开，则移除视频焦点
        } else {
          _restoreFocus(); // 如果抽屉关闭，延迟恢复视频区域焦点
        }
      });
    }, '处理抽屉状态变化时发生错误');
  }

  @override
  void dispose() {
    LogUtil.safeExecute(() {
      _timer?.cancel(); // 销毁定时器，防止内存泄漏
      _videoNode.dispose(); // 销毁焦点节点
      widget.controller?.dispose(); // 销毁视频控制器，释放资源
      super.dispose(); // 调用父类的 dispose 方法
    }, '释放资源时发生错误');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 设置背景为黑色
      drawer: ChannelDrawerPage( // 侧边抽屉，显示频道列表
        videoMap: widget.videoMap,
        playModel: widget.playModel,
        onTapChannel: widget.onTapChannel,
        isLandscape: true,
      ),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.3, // 侧边抽屉的拖拽宽度
      drawerScrimColor: Colors.transparent, // 抽屉背景透明
      onDrawerChanged: _handleDrawerChange, // 当抽屉打开或关闭时调用的回调函数
      body: Builder(builder: (context) {
        return KeyboardListener(
          focusNode: _videoNode, // 将焦点绑定到视频区域
          autofocus: true, // 自动获取焦点
          onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e), // 处理键盘事件
          child: widget.toastString == 'UNKNOWN'
              ? EmptyPage(onRefresh: () => widget.onChangeSubSource?.call()) // 如果没有视频源，显示空页面并提供刷新操作
              : Container(
                  alignment: Alignment.center, // 内容居中对齐
                  color: Colors.black, // 设置背景为黑色
                  child: Stack( // 使用堆叠布局，将视频播放器和其他 UI 组件叠加在一起
                    alignment: Alignment.center, // 堆叠的子组件居中对齐
                    children: [
                      widget.controller?.value.isInitialized == true
                          ? AspectRatio(
                              aspectRatio: widget.aspectRatio, // 设置视频宽高比
                              child: SizedBox(
                                width: double.infinity, // 占满宽度
                                child: VideoPlayer(widget.controller!), // 显示视频播放器
                              ),
                            )
                          : VideoHoldBg(
                              toastString: _drawerIsOpen ? '' : widget.toastString, // 显示背景及提示文字
                              videoController: widget.controller!,
                            ),
                      if (_drawerIsOpen) const DatePositionWidget(), // 如果抽屉打开，显示时间和位置信息
                      if (!widget.isPlaying && !_drawerIsOpen)
                        GestureDetector(
                            onTap: () {
                              widget.controller?.play(); // 如果视频暂停，点击图标时播放视频
                            },
                            child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 50)), // 播放按钮
                      if (widget.isBuffering && !_drawerIsOpen) const SpinKitSpinningLines(color: Colors.white), // 显示缓冲动画
                      if (_isError && !_drawerIsOpen)
                        Center(child: Text(S.of(context).playError,style: TextStyle(color: Colors.red))), // 显示错误提示
                    ],
                  ),
                ),
        );
      }),
    );
  }
}
