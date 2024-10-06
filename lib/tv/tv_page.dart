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

  // 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_isSourceSelectionVisible) {
      // 如果视频源选择框打开，关闭它
      setState(() {
        _isSourceSelectionVisible = false;
      });
      return false; // 不退出页面
    }

    if (_drawerIsOpen) {
      // 如果抽屉打开则关闭抽屉
      setState(() {
        _drawerIsOpen = false;
      });
      return false;
    }

    // 弹出退出确认对话框
    return await ShowExitConfirm.ExitConfirm(context);
  }

  // 处理选择键逻辑
  Future<void> _handleSelectPress() async {
    if (_isSourceSelectionVisible) {
      // 如果源选择已经显示，执行播放或暂停操作
      if (widget.isPlaying) {
        widget.controller?.pause(); // 暂停视频播放
      } else {
        widget.controller?.play(); // 播放视频
      }
      setState(() {
        _isSourceSelectionVisible = false; // 关闭视频源选择
      });
    } else {
      // 显示视频源选择界面
      setState(() {
        _isSourceSelectionVisible = true;
      });

      // 启动计时器，如果计时器内再次点击选择键则执行播放操作
      _pauseIconTimer?.cancel();
      _pauseIconTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
          _isSourceSelectionVisible = false;
        });
      });
    }
  }

  // 处理键盘事件的函数，处理遥控器输入
  Future<void> _focusEventHandle(BuildContext context, KeyEvent e) async {
    _handleDebounce(() async {
      if (e is! KeyUpEvent) return; // 只处理按键释放事件

      if (_drawerIsOpen) {
        return; // 阻止方向键在抽屉打开时响应全局事件
      }

      // 根据按键的不同逻辑键值执行相应的操作
      switch (e.logicalKey) {
        case LogicalKeyboardKey.arrowRight:
          // 处理右键操作
          break;
        case LogicalKeyboardKey.arrowLeft:
          // 处理左键操作
          break;
        case LogicalKeyboardKey.arrowUp:
          await widget.changeChannelSources?.call(); // 切换视频源
          break;
        case LogicalKeyboardKey.arrowDown:
          widget.controller?.pause(); // 暂停视频播放
          await _openAddSource(); // 打开设置页面以添加新的视频源
          final m3uData = SpUtil.getString('m3u_cache', defValue: '')!;
          if (m3uData == '') {
            widget.onChangeSubSource?.call(); // 如果没有视频源，调用切换回调
          } else {
            widget.controller?.play(); // 如果有视频源，恢复视频播放
          }
          break;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter: // 处理选择键和 Enter 键
          setState(() {
            _isDatePositionVisible = !_isDatePositionVisible; // 切换 DatePositionWidget 显示与隐藏
          });
          await _handleSelectPress(); // 调用选择键的处理逻辑
          break;
        case LogicalKeyboardKey.goBack:
          _handleBackPress(context); // 修改的返回键逻辑
          break;
        case LogicalKeyboardKey.contextMenu:
          setState(() {
            _drawerIsOpen = true; // 打开侧边抽屉菜单
          });
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
    LogUtil.safeExecute(() {
      _timer?.cancel(); // 销毁定时器，防止内存泄漏
      _pauseIconTimer?.cancel(); // 取消暂停图标计时器
      widget.controller?.dispose(); // 销毁视频控制器，释放资源
      super.dispose(); // 调用父类的 dispose 方法
    }, '释放资源时发生错误');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope( // 添加返回键拦截逻辑
      onWillPop: () => _handleBackPress(context), // 处理返回键的逻辑
      child: Scaffold(
        backgroundColor: Colors.black, // 设置背景为黑色
        body: Builder(builder: (context) {
          return KeyboardListener(
            focusNode: FocusNode(),  // 必须提供 focusNode，即便不需要手动管理焦点
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
                        widget.controller != null && widget.controller!.value.isInitialized
                            ? AspectRatio(
                                aspectRatio: widget.controller!.value.aspectRatio, // 动态获取视频宽高比
                                child: SizedBox(
                                  width: double.infinity, // 占满宽度
                                  child: VideoPlayer(widget.controller!), // 显示视频播放器
                                ),
                              )
                            : VideoHoldBg(
                                toastString: _drawerIsOpen ? '' : widget.toastString, // 显示背景及提示文字
                                videoController: widget.controller ?? VideoPlayerController.network(''),
                              ),
                        
                        // 按下 select 或 Enter 键时显示或隐藏 DatePositionWidget
                        if (_isDatePositionVisible) const DatePositionWidget(),

                        // 如果正在缓冲或出现错误，显示进度条和提示
                        if ((widget.isBuffering || _isError) && !_drawerIsOpen)
                          Align(
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
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      return _buildToast(S.of(context).loading);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Offstage 控制 ChannelDrawerPage 的显示和隐藏
                        Offstage(
                          offstage: !_drawerIsOpen, // 控制 ChannelDrawerPage 显示与隐藏
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _drawerIsOpen = false; // 点击抽屉区域外时，关闭抽屉
                              });
                            },
                            child: ChannelDrawerPage(
                              videoMap: widget.videoMap,
                              playModel: widget.playModel,
                              onTapChannel: _handleEPGProgramTap, // 在 ChannelDrawerPage 中点击节目时关闭抽屉
                              isLandscape: true,
                              onCloseDrawer: () { // 添加 onCloseDrawer 参数
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

  Widget _buildToast(String message) {
    return Text(
      message,
      style: TextStyle(color: Colors.white, fontSize: 18),
    );
  }
}
