import 'dart:async';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
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
  // 添加常量定义暂停图标显示时间
  static const Duration _pauseIconDisplayDuration = Duration(seconds: 3);
  
  bool _drawerIsOpen = false; // 频道抽屉是否打开
  bool _isShowPauseIcon = false; // 是否显示暂停图标
  bool _isShowPlayIcon = false; // 新增：是否显示播放图标
  Timer? _pauseIconTimer; // 暂停图标显示的计时器
  bool _isDatePositionVisible = false; // 控制 DatePositionWidget 显示隐藏
  bool _isError = false; // 标识是否播放过程中发生错误
  bool _blockSelectKeyEvent = false; // 新增：用于阻止选择键事件
  // 添加 TvKeyNavigationState 用于控制焦点管理
  TvKeyNavigationState? _drawerNavigationState;
  ValueKey<int>? _drawerRefreshKey; // 刷新键状态
// 打开设置页面
  Future<bool?> _opensetting() async {
    try {
      // 在打开设置页面前设置播放图标显示
      setState(() {
        _isShowPlayIcon = true;
      });
      
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
  
  // 处理返回按键逻辑 - 已修改
  Future<bool> _handleBackPress(BuildContext context) async {
    // 如果抽屉是打开的，则关闭抽屉
    if (_drawerIsOpen) {
      _toggleDrawer(false);
      return false;
    }

    // 如果抽屉已关闭，且没有其他页面可返回时，显示退出确认对话框
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    } else {
      // 在显示退出确认对话框前检查视频状态并暂停
      bool wasPlaying = widget.controller?.value.isPlaying ?? false;
      if (wasPlaying) {
        await widget.controller?.pause();
        // 添加显示播放图标
        setState(() {
          _isShowPlayIcon = true;
        });
      }
      
      // 显示退出确认对话框
      bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
      
      // 如果取消退出且视频之前在播放，则恢复播放并隐藏播放图标
      if (!shouldExit && wasPlaying) {
        await widget.controller?.play();
        setState(() {
          _isShowPlayIcon = false;
        });
      }
      
      return shouldExit;
    } 
  }

  // 保持原有的控制图标构建方法不变
  Widget _buildControlIcon({
    required IconData icon,
    Color backgroundColor = Colors.black,
    Color iconColor = Colors.white,
  }) {
    return Center(
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
  }

  // 构建暂停图标
  Widget _buildPauseIcon() {
    return _buildControlIcon(icon: Icons.pause);
  }

  // 构建播放图标
  Widget _buildPlayIcon() {
    return _buildControlIcon(icon: Icons.play_arrow);
  }
  
// 保持原有的选择键处理逻辑不变
  Future<void> _handleSelectPress() async {
    // 1. 如果视频正在播放
    if (widget.isPlaying) {
      // 1.1 如果没有定时器在运行
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 1.11 如果正在播放中，显示暂停图标，并启动定时器
        setState(() {
          _isShowPauseIcon = true;
          _isShowPlayIcon = false;  // 确保播放图标隐藏
        });
        _pauseIconTimer = Timer(_pauseIconDisplayDuration, () {
          if (mounted) {
            setState(() {
              _isShowPauseIcon = false;
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
      if (widget.controller != null && !widget.controller!.value.isPlaying) {
        await widget.controller?.play();
        setState(() {
          _isShowPlayIcon = false;  // 隐藏播放图标
        });
      }
    }

    // 2. 无论视频是否正在播放，都切换时间和收藏图标的显示状态
    setState(() {
      _isDatePositionVisible = !_isDatePositionVisible;
    });
  }
  
// 处理键盘事件的函数 - 修改了下方向键处理部分
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
          
          // 触发抽屉刷新
          setState(() {
            _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
          });
          
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
        _toggleDrawer(!_drawerIsOpen);
        break;
      case LogicalKeyboardKey.arrowUp:   // 处理上键操作
        await widget.changeChannelSources?.call(); // 切换视频源
        break;
      case LogicalKeyboardKey.arrowDown:   // 处理下键操作
        widget.controller?.pause(); // 暂停视频播放
        setState(() {
          _isShowPlayIcon = true;  // 显示播放图标
        });
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
  
// 保持 EPGList 节目点击事件处理不变
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    _blockSelectKeyEvent = true; // 标记需要阻止选择键事件
    widget.onTapChannel?.call(selectedProgram); // 切换到选中的节目
    _toggleDrawer(false);
    
    // 500ms 后重置阻止标记
    Future.delayed(const Duration(milliseconds: 500), () {
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
    _isShowPlayIcon = false; // 新增：重置播放图标状态
    _isShowPauseIcon = false; // 新增：重置暂停图标状态
    if (_drawerNavigationState != null) {
      _drawerNavigationState!.deactivateFocusManagement();
      _drawerNavigationState = null;
    }
    super.dispose(); // 调用父类的 dispose 方法
  }
  
// 保持收藏图标构建方法不变
  Widget _buildFavoriteIcon() {
    if (widget.currentChannelId == null || widget.isChannelFavorite == null) {
      return const SizedBox(); // 如果没有必要的数据，返回空组件
    }

    return Positioned(
      right: 28,
      bottom: 28,
      child: Icon(
        widget.isChannelFavorite!(widget.currentChannelId!) 
            ? Icons.favorite 
            : Icons.favorite_border,
        color: widget.isChannelFavorite!(widget.currentChannelId!) 
            ? Colors.red 
            : Colors.white,
        size: 38, // 收藏图标大小
      ),
    );
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
                  // 使用 ValueListenableBuilder 监听视频控制器状态变化
                  ValueListenableBuilder<VideoPlayerValue?>(
                    valueListenable: widget.controller ?? ValueNotifier<VideoPlayerValue?>(null),
                    builder: (BuildContext context, VideoPlayerValue? value, Widget? child) {
                      if (widget.controller != null && value?.isInitialized == true) {
                        return AspectRatio(
                          aspectRatio: value!.aspectRatio,
                          child: SizedBox(
                            width: double.infinity,
                            child: VideoPlayer(widget.controller!),
                          ),
                        );
                      }
                      return VideoHoldBg(
                        toastString: _drawerIsOpen ? '' : widget.toastString,
                        videoController: VideoPlayerController.network(''),
                      );
                    },
                  ),
                  
                  // 显示暂停图标
                  if (_isShowPauseIcon) 
                    _buildPauseIcon(),
                    
                  // 修改后的播放图标显示逻辑，使用 _isShowPlayIcon 来控制
                  if (_isShowPlayIcon &&
                      widget.controller != null && 
                      widget.controller!.value.isInitialized && 
                      !widget.controller!.value.isPlaying)
                    _buildPlayIcon(),

                  // 显示日期位置组件
                  if (_isDatePositionVisible) const DatePositionWidget(),
                  
                  // 添加收藏图标显示 - 仅在显示时间时显示
                  if (_isDatePositionVisible && !_drawerIsOpen) 
                    _buildFavoriteIcon(),
                 
                  // 显示缓冲指示器
                  if (widget.controller != null &&
                      widget.controller!.value.isInitialized &&
                      (widget.isBuffering || _isError) && !_drawerIsOpen)
                    _buildBufferingIndicator(),

                  // 频道抽屉显示
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Offstage(
                      offstage: !_drawerIsOpen,
                      child: ChannelDrawerPage(
                        key: _drawerRefreshKey ?? const ValueKey('channel_drawer'), 
                        refreshKey: _drawerRefreshKey, // 传递刷新键
                        videoMap: widget.videoMap, // 播放列表模型
                        playModel: widget.playModel, // 当前播放频道模型
                        isLandscape: true, // 横屏显示
                        onTapChannel: _handleEPGProgramTap,
                        onCloseDrawer: () {
                          _toggleDrawer(false);
                        },
                        onTvKeyNavigationStateCreated: (state) {
                          setState(() {
                            _drawerNavigationState = state;
                          });
                          // 确保在状态设置后再根据抽屉状态设置焦点管理
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_drawerIsOpen) {
                              state.activateFocusManagement();
                            } else {
                              state.deactivateFocusManagement();
                            }
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
  
// 管理抽屉显示/隐藏和焦点管理的方法
  void _toggleDrawer(bool isOpen) {
    if (_drawerIsOpen == isOpen) return;

    setState(() {
      _drawerIsOpen = isOpen;
    });

    // 根据抽屉状态控制焦点管理
    if (_drawerNavigationState != null) {
      if (isOpen) {
        _drawerNavigationState!.activateFocusManagement();
      } else {
        _drawerNavigationState!.deactivateFocusManagement();
      }
    }
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
