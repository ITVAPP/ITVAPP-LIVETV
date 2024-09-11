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

  // 显示错误信息的工具函数
  void _showError(String message) {
    setState(() {
      _isError = true; // 设置错误状态
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); // 显示错误提示
      LogUtil.logError('播放错误：$message', Exception(message));
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

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
    } catch (e, stackTrace) {
      LogUtil.logError('打开添加源设置页面时发生错误', e, stackTrace);
      return null;
    }
  }

  // 处理键盘事件的函数，处理遥控器输入
  Future<void> _focusEventHandle(BuildContext context, KeyEvent e) async {
    try {
      if (e is! KeyUpEvent || !_debounce) return; // 如果不是按键释放事件或节流未恢复，则直接返回
      _debounce = false; // 防止短时间内再次触发
      _timer = Timer(const Duration(milliseconds: 300), () {
        _debounce = true; // 恢复节流状态
        _timer?.cancel(); // 取消定时器
        _timer = null;
      });

      // 根据按键的不同逻辑键值执行相应的操作
      switch (e.logicalKey) {
        case LogicalKeyboardKey.arrowRight:
          LogUtil.v('按了右键'); // 处理右键操作
          break;
        case LogicalKeyboardKey.arrowLeft:
          LogUtil.v('按了左键'); // 处理左键操作
          break;
        case LogicalKeyboardKey.arrowUp:
          LogUtil.v('按了上键');
          _videoNode.unfocus(); // 移除视频区域的焦点
          await widget.changeChannelSources?.call(); // 切换视频源
          Future.delayed(const Duration(seconds: 1), () => _videoNode.requestFocus()); // 延迟恢复焦点
          break;
        case LogicalKeyboardKey.arrowDown:
          LogUtil.v('按了下键');
          widget.controller?.pause(); // 暂停视频播放
          _videoNode.unfocus(); // 移除焦点
          await _openAddSource(); // 打开设置页面
          final m3uData = SpUtil.getString('m3u_cache', defValue: '')!;
          if (m3uData == '') {
            widget.onChangeSubSource?.call(); // 如果没有视频源，调用切换回调
          } else {
            widget.controller?.play(); // 恢复视频播放
          }
          Future.delayed(const Duration(seconds: 1), () => _videoNode.requestFocus()); // 延迟恢复焦点
          break;
        case LogicalKeyboardKey.select:
          LogUtil.v('按了确认键');
          if (_isError) {
            _showError('视频加载失败，请重试'); // 如果出现错误，显示提示信息
            return;
          }

          if (widget.controller?.value.isInitialized == true &&
              !widget.controller!.value.isPlaying &&
              !widget.controller!.value.isBuffering) {
            widget.controller?.play(); // 如果未播放且未缓冲，开始播放
          } else {
            LogUtil.v('确认键:::打开频道列表');
            if (!Scaffold.of(context).isDrawerOpen) {
              Scaffold.of(context).openDrawer(); // 打开频道抽屉
            }
          }
          break;
        case LogicalKeyboardKey.goBack:
          LogUtil.v('按了返回键');
          Navigator.pop(context); // 返回上一个页面
          break;
        case LogicalKeyboardKey.contextMenu:
          LogUtil.v('按了菜单键');
          if (!Scaffold.of(context).isDrawerOpen) {
            Scaffold.of(context).openDrawer(); // 打开频道抽屉
          }
          break;
        case LogicalKeyboardKey.audioVolumeUp:
          LogUtil.v('按了音量加键');
          break;
        case LogicalKeyboardKey.audioVolumeDown:
          LogUtil.v('按了音量减键');
          break;
        case LogicalKeyboardKey.f5:
          LogUtil.v('按了语音键');
          break;
        default:
          break;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('处理键盘事件时发生错误', e, stackTrace);
    }
  }

  @override
  void dispose() {
    LogUtil.safeExecute(() {
      _timer?.cancel(); // 销毁定时器
      _videoNode.dispose(); // 销毁焦点节点
      super.dispose();
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
      onDrawerChanged: (bool isOpen) {
        LogUtil.safeExecute(() {
          setState(() {
            _drawerIsOpen = isOpen;
            if (_drawerIsOpen) {
              _videoNode.unfocus(); // 抽屉打开时移除视频焦点
            } else {
              Future.delayed(const Duration(milliseconds: 100), () {
                _videoNode.requestFocus(); // 抽屉关闭时延迟恢复焦点
              });
            }
          });
        }, '处理抽屉状态变化时发生错误');
      },
      body: Builder(builder: (context) {
        return KeyboardListener(
          focusNode: _videoNode, // 将焦点绑定到视频区域
          autofocus: true, // 自动获取焦点
          onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e), // 处理键盘事件
          child: widget.toastString == 'UNKNOWN'
              ? EmptyPage(onRefresh: () => widget.onChangeSubSource?.call()) // 如果没有视频源，显示空页面
              : Container(
                  alignment: Alignment.center, // 居中对齐
                  color: Colors.black, // 设置背景为黑色
                  child: Stack( // 使用堆叠布局
                    alignment: Alignment.center, // 居中对齐
                    children: [
                      widget.controller?.value.isInitialized == true
                          ? AspectRatio(
                              aspectRatio: widget.aspectRatio, // 设置视频宽高比
                              child: SizedBox(
                                width: double.infinity,
                                child: VideoPlayer(widget.controller!), // 播放视频
                              ),
                            )
                          : VideoHoldBg(
                              toastString: _drawerIsOpen ? '' : widget.toastString, // 显示背景及提示文字
                              videoController: widget.controller!,
                            ),
                      if (_drawerIsOpen) const DatePositionWidget(), // 打开抽屉时显示时间和位置信息
                      if (!widget.isPlaying && !_drawerIsOpen)
                        GestureDetector(
                            onTap: () {
                              widget.controller?.play(); // 点击图标时播放视频
                            },
                            child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 50)),
                      if (widget.isBuffering && !_drawerIsOpen) const SpinKitSpinningLines(color: Colors.white), // 显示缓冲动画
                      if (_isError && !_drawerIsOpen)
                        Center(child: Text('播放错误，请重试', style: TextStyle(color: Colors.red))), // 显示错误提示
                    ],
                  ),
                ),
        );
      }),
    );
  }
}
