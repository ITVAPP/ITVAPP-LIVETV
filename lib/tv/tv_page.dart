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
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return; // 不处理非按键按下事件

    // 如果抽屉打开，只处理返回键和菜单键
    if (_drawerIsOpen) {
      if (event.logicalKey == LogicalKeyboardKey.goBack || 
          event.logicalKey == LogicalKeyboardKey.contextMenu) {
        _handleDebounce(() {
          setState(() {
            _drawerIsOpen = false;
          });
        });
      }
      return;
    }

    _handleDebounce(() async {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.contextMenu:
        case LogicalKeyboardKey.arrowRight:
          if (!_drawerIsOpen) {
            setState(() {
              _drawerIsOpen = true;
            });
          }
          break;
        case LogicalKeyboardKey.arrowLeft:
          if (!_drawerIsOpen) {
            await widget.changeChannelSources?.call();
          }
          break;
        case LogicalKeyboardKey.arrowUp:
          setState(() {
            _isSourceSelectionVisible = !_isSourceSelectionVisible;
          });
          break;
        case LogicalKeyboardKey.arrowDown:
          if (!_drawerIsOpen) {
            widget.controller?.pause();
            await _opensetting();
          }
          break;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          if (!_drawerIsOpen) {
            await _handleSelectPress();
          }
          break;
        case LogicalKeyboardKey.goBack:
          await _handleBackPress(context);
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

  // 处理 EPGList 节目点击事件，确保点击后抽屉关闭
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    widget.onTapChannel?.call(selectedProgram); // 切换到选中的节目
    setState(() {
      _drawerIsOpen = false; // 点击节目后关闭抽屉
    });
  }

  @override
  void dispose() {
    // 资源释放优化：确保每个资源释放操作都在独立的 try-catch 中执行
    try {
      _timer?.cancel();
    } catch (e) {
      LogUtil.logError('释放 _timer 失败', e);
    }
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
                        // 修改部分：视频未初始化或未播放时，显示 VideoHoldBg
                        if (widget.controller?.value.isInitialized != true || !widget.controller!.value.isPlaying)
                          VideoHoldBg(
                            toastString: _drawerIsOpen ? '' : widget.toastString, 
                            videoController: widget.controller ?? VideoPlayerController.network(''),
                          ),

                        // 修改部分：视频初始化且正在播放时，显示视频播放器
                        if (widget.controller?.value.isInitialized == true && widget.controller!.value.isPlaying)
                          AspectRatio(
                            aspectRatio: widget.controller!.value.aspectRatio, // 动态获取视频宽高比
                            child: SizedBox(
                              width: double.infinity, // 占满宽度
                              child: VideoPlayer(widget.controller!), // 显示视频播放器
                            ),
                          ),

                        if (_isDatePositionVisible) const DatePositionWidget(),

                        // 修改部分：仅在视频暂停时显示播放图标
                        if (widget.controller!.value.isInitialized == true && !widget.controller!.value.isPlaying)
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.5), // 半透明圆形背景
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.7), // 阴影颜色
                                    spreadRadius: 2, // 阴影扩展
                                    blurRadius: 10, // 模糊半径
                                    offset: Offset(0, 3), // 阴影偏移
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(20.0), // 图标的内边距
                              child: Icon(
                                Icons.play_arrow,
                                size: 64,
                                color: Colors.white.withOpacity(0.85),
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
