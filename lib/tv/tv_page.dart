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

  VideoPlayerController? controller; // 视频播放器控制器
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
  bool _debounce = true; // 防止按键被快速多次触发
  Timer? _timer; // 定时器用于处理按键节流
  bool _drawerIsOpen = false; // 侧边抽屉是否打开
  bool _isSourceSelectionVisible = false; // 视频源选择是否显示
  bool _isShowPauseIcon = false; // 是否显示暂停图标
  Timer? _pauseIconTimer; // 暂停图标显示的计时器
  bool _isDatePositionVisible = false; // 控制 DatePositionWidget 显示隐藏

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

  // 处理频道切换逻辑
  Future<void> _handleChannelSwitch() async {
    setState(() {
      // 切换频道时，先将视频控制器置空，并显示 VideoHoldBg
      widget.controller = null;
    });

    try {
      // 切换频道，并重新初始化视频控制器
      await widget.changeChannelSources?.call();

      if (widget.controller != null) {
        widget.controller!.initialize().then((_) {
          setState(() {});  // 初始化完成后重绘页面，显示视频
        }).catchError((error) {
          LogUtil.logError('切换频道时视频初始化失败', error);
        });
      }
    } catch (e) {
      LogUtil.logError('切换频道失败', e);
    }
  }

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
    if (_isSourceSelectionVisible || _drawerIsOpen) {
      // 合并状态更新以减少重绘
      setState(() {
        _isSourceSelectionVisible = false;
        _drawerIsOpen = false;
      });
      return false; // 不退出页面
    }

    // 弹出退出确认对话框
    return await ShowExitConfirm.ExitConfirm(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope( // 添加返回键拦截逻辑
      onWillPop: () => _handleBackPress(context), // 处理返回键的逻辑
      child: Scaffold(
        backgroundColor: Colors.black, // 设置背景为黑色
        body: Builder(builder: (context) {
          return RawKeyboardListener(
            focusNode: FocusNode(),
            onKey: _handleKeyEvent,  // 使用新的事件处理函数
            child: widget.toastString == 'UNKNOWN'
                ? EmptyPage(onRefresh: () => widget.onChangeSubSource?.call()) // 如果没有视频源，显示空页面并提供刷新操作
                : Container(
                    alignment: Alignment.center, // 内容居中对齐
                    color: Colors.black, // 设置背景为黑色
                    child: Stack( // 使用堆叠布局，将视频播放器和其他 UI 组件叠加在一起
                      children: [
                        // 初始状态以及视频未加载完成时，显示 VideoHoldBg
                        widget.controller == null || !widget.controller!.value.isInitialized
                            ? VideoHoldBg(
                                toastString: widget.toastString ?? '加载中...', // 显示背景及提示文字
                                videoController: widget.controller ?? VideoPlayerController.network(''),
                              )
                            : AspectRatio(
                                aspectRatio: widget.controller!.value.aspectRatio, // 动态获取视频宽高比
                                child: SizedBox(
                                  width: double.infinity, // 占满宽度
                                  child: VideoPlayer(widget.controller!), // 显示视频播放器
                                ),
                              ),
                        if (_isDatePositionVisible) const DatePositionWidget(),
                        // 仅当视频暂停时显示圆形播放图标，带有阴影效果
                        if (widget.controller != null && widget.controller!.value.isInitialized && !widget.controller!.value.isPlaying)
                          Center(
                            child: Container(
                              width: 98,  // 圆形按钮的宽度
                              height: 98,  // 圆形按钮的高度
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),  // 半透明的白色背景
                                shape: BoxShape.circle,  // 设置为圆形
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),  // 阴影颜色，黑色带透明度
                                    spreadRadius: 2,  // 阴影扩散半径
                                    blurRadius: 8,  // 阴影模糊程度
                                    offset: Offset(0, 4),  // 阴影偏移量
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.play_arrow,
                                size: 78,  // 图标大小
                                color: Colors.white,  // 图标颜色
                              ),
                            ),
                          ),
                        if ((widget.isBuffering || _isError) && !_drawerIsOpen)
                          _buildBufferingIndicator(),
                        if (_drawerIsOpen)  // 修改抽屉显示逻辑
                          Positioned( // 使用 Positioned 来控制抽屉位置
                            left: 0, // 确保抽屉从左边开始
                            top: 0, // 从顶部开始
                            bottom: 0, // 延伸到底部
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _drawerIsOpen = false;
                                });
                              },
                              child: ChannelDrawerPage(
                                videoMap: widget.videoMap,
                                playModel: widget.playModel,
                                onTapChannel: _handleEPGProgramTap,
                                isLandscape: true,
                                onCloseDrawer: () {
                                  setState(() {
                                    _drawerIsOpen = false;
                                  });
                                },
                              ),
                            ),
                          ),
                      ],
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
