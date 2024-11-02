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
  
  // 新增收藏相关属性
  final Function(String)? toggleFavorite;        // 切换收藏状态的回调
  final Function(String)? isChannelFavorite;     // 检查收藏状态的回调
  final String? currentChannelId;                // 当前频道ID

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
    // 新增收藏参数
    this.toggleFavorite,
    this.isChannelFavorite,
    this.currentChannelId,
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> with TickerProviderStateMixin {
  bool _drawerIsOpen = false; // 频道抽屉是否打开
  bool _isShowPauseIcon = false; // 是否显示暂停图标
  Timer? _pauseIconTimer; // 暂停图标显示的计时器
  bool _isDatePositionVisible = false; // 控制 DatePositionWidget 显示隐藏
  bool _isError = false; // 标识是否播放过程中发生错误
  bool _blockSelectKeyEvent = false; // 新增：用于阻止选择键事件

  // 打开设置页面
  Future<bool?> _opensetting() async {
    try {
      return Navigator.push<bool>( // 使用 Navigator 打开新的页面
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
    // 如果抽屉是打开的，则关闭抽屉
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;
      });
      return false;
    }

    // 如果抽屉已关闭，且没有其他页面可返回时，显示退出确认对话框
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    } else {
      return await ShowExitConfirm.ExitConfirm(context);
    } 
  }

  // 处理选择键逻辑  
  Future<void> _handleSelectPress() async {
    // 合并状态更新以减少重绘
    setState(() {
      _isDatePositionVisible = !_isDatePositionVisible; // 切换日期位置组件显示
      _isShowPauseIcon = widget.isPlaying; // 根据当前播放状态显示暂停图标
    });

    // 启动计时器控制暂停图标显示时间
    if (widget.isPlaying) {
      _pauseIconTimer?.cancel(); // 取消之前的计时器
      _pauseIconTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
          _isShowPauseIcon = false; // 3秒后隐藏暂停图标
        });
      });
    } else {
      // 播放视频并确保暂停图标不显示
      widget.controller?.play();
      setState(() {
        _isShowPauseIcon = false; // 播放时不显示暂停图标
      });
    }
  }
  
  // 处理键盘事件的函数，处理遥控器输入
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled; // 只处理按键释放事件

    // 仅在抽屉打开时阻止方向键、选择键和确认键
    if (_drawerIsOpen && (e.logicalKey == LogicalKeyboardKey.arrowUp ||
                          e.logicalKey == LogicalKeyboardKey.arrowDown ||
                          e.logicalKey == LogicalKeyboardKey.arrowLeft ||
                          e.logicalKey == LogicalKeyboardKey.arrowRight ||
                          e.logicalKey == LogicalKeyboardKey.select ||
                          e.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.handled; // 阻止相关按键
    }

    // 根据按键的不同逻辑键值执行相应的操作
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:  // 添加左键收藏功能
        if (widget.toggleFavorite != null && 
            widget.isChannelFavorite != null && 
            widget.currentChannelId != null) {
          
          final bool isFavorite = widget.isChannelFavorite!(widget.currentChannelId!);
          widget.toggleFavorite!(widget.currentChannelId!);
          
          // 使用 CustomSnackBar 显示操作结果
          if (mounted) {
            CustomSnackBar.showSnackBar(
              context,
              isFavorite ? S.of(context).removefavorite : S.of(context).newfavorite,
              duration: const Duration(seconds: 4),
            );
          }
        }
        break;
      case LogicalKeyboardKey.arrowRight:  // 处理右键操作
        setState(() {
          _drawerIsOpen = true;  // 打开频道抽屉菜单
        });
        break;
      case LogicalKeyboardKey.arrowUp:   // 处理上键操作
        await widget.changeChannelSources?.call(); // 切换视频源
        break;
      case LogicalKeyboardKey.arrowDown:   // 处理下键操作
        widget.controller?.pause(); // 暂停视频播放	
        _opensetting(); // 打开设置页面
        break;
      case LogicalKeyboardKey.select: // 处理选择键
      case LogicalKeyboardKey.enter:  // 处理确认键
        // 只有在不阻止选择键事件时才处理
        if (!_blockSelectKeyEvent) {
          await _handleSelectPress();
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
    return KeyEventResult.handled;  // 返回 KeyEventResult.handled
  }
  
  // 处理 EPGList 节目点击事件，确保点击后抽屉关闭
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    _blockSelectKeyEvent = true; // 标记需要阻止选择键事件
    widget.onTapChannel?.call(selectedProgram); // 切换到选中的节目
    setState(() {
      _drawerIsOpen = false; // 点击节目后关闭抽屉
    });
    
    // 300ms 后重置阻止标记
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) { // 确保 widget 还在树中
        setState(() {
          _blockSelectKeyEvent = false;
        });
      }
    });
  }
  
  @override
  void dispose() {
    try {
      _pauseIconTimer?.cancel(); // 释放暂停图标计时器
    } catch (e) {
      LogUtil.logError('释放 _pauseIconTimer 失败', e); // 记录释放失败的错误
    }
    try {
      widget.controller?.dispose(); // 释放视频控制器
    } catch (e) {
      LogUtil.logError('释放 controller 失败', e); // 记录释放失败的错误
    }
    _blockSelectKeyEvent = false; // 重置阻止标记
    super.dispose(); // 调用父类的 dispose 方法
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBackPress(context), // 确保在退出前调用
      child: Scaffold(
        backgroundColor: Colors.black, // 设置背景颜色为黑色
        body: Builder(builder: (context) {
          return KeyboardListener(
            focusNode: FocusNode(),  
            onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e), // 处理键盘事件
            child: Container(
              alignment: Alignment.center, // 组件居中对齐
              color: Colors.black, // 设置容器背景颜色为黑色
              child: Stack(
                children: [
                  // 显示视频播放器
                  if (widget.controller != null && widget.controller!.value.isInitialized)
                    AspectRatio(
                      aspectRatio: widget.controller!.value.aspectRatio, // 根据视频控制器的宽高比设置
                      child: SizedBox(
                        width: double.infinity,
                        child: VideoPlayer(widget.controller!), // 创建视频播放器组件
                      ),
                    )
                  // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                  else
                    VideoHoldBg(
                      toastString: _drawerIsOpen ? '' : widget.toastString, // 显示提示信息
                      videoController: VideoPlayerController.network(''), // 为空的网络视频控制器
                    ),
                    // 仅在视频播放器显示且视频暂停时显示播放图标
                  if (widget.controller != null && widget.controller!.value.isInitialized && !widget.controller!.value.isPlaying)
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, // 设置形状为圆形
                          color: Colors.black.withOpacity(0.5), // 半透明黑色背景
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.7), // 阴影颜色
                              spreadRadius: 2, // 阴影扩散半径
                              blurRadius: 10, // 阴影模糊半径
                              offset: const Offset(0, 3), // 阴影偏移量
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10.0), // 设置内边距
                        child: Icon(
                          Icons.play_arrow, // 播放图标
                          size: 78,
                          color: Colors.white.withOpacity(0.85), // 半透明白色
                        ),
                      ),
                    ),

                  // 显示日期位置组件
                  if (_isDatePositionVisible) const DatePositionWidget(),

                  // 显示缓冲指示器
                  if (widget.controller != null &&
                      widget.controller!.value.isInitialized &&
                      (widget.isBuffering || _isError) && !_drawerIsOpen)
                    _buildBufferingIndicator(),

                  // 频道抽屉显示 - 修改后的实现
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Offstage(
                      offstage: !_drawerIsOpen,
                      child: ChannelDrawerPage(
                        videoMap: widget.videoMap, // 播放列表模型
                        playModel: widget.playModel, // 当前播放频道模型
                        isLandscape: true, // 横屏显示
                        onTapChannel: _handleEPGProgramTap,
                        onCloseDrawer: () {
                          setState(() {
                            _drawerIsOpen = false; // 点击后关闭抽屉
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
  
  // 构建缓冲指示器
  Widget _buildBufferingIndicator() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0), // 设置底部边距
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(
              width: MediaQuery.of(context).size.width * 0.3, // 设置进度条宽度
              height: 5, // 设置进度条高度
            ),
            const SizedBox(height: 8), // 设置进度条和提示信息之间的间距
            _buildToast(S.of(context).loading), // 显示加载提示信息
          ],
        ),
      ),
    );
  }

  // 构建提示信息组件
  Widget _buildToast(String message) {
    return Text(
      message, // 显示提示信息
      style: TextStyle(color: Colors.white, fontSize: 18), // 设置字体颜色和大小
    );
  }
}
