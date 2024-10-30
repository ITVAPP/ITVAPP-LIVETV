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

// 定义层级枚举，明确优先级
enum OverlayLayer {
  none,
  sourceSelection,  // 最低优先级
  drawer,
  settings,
  dialog,          // 最高优先级
}

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
  // 添加返回事件处理锁
  static bool _isProcessingBack = false;
  
  bool _debounce = true; // 防止按键被快速多次触发
  Timer? _timer; // 定时器用于处理按键节流
  bool _isShowPauseIcon = false; // 是否显示暂停图标
  Timer? _pauseIconTimer; // 暂停图标显示的计时器
  bool _isDatePositionVisible = false; // 控制 DatePositionWidget 显示隐藏
  bool _isError = false; // 标识是否播放过程中发生错误

  // 使用单一状态来管理当前层
  OverlayLayer _currentLayer = OverlayLayer.none;
  
  // 便捷的判断方法
  bool get hasOverlay => _currentLayer != OverlayLayer.none;
  bool get _drawerIsOpen => _currentLayer == OverlayLayer.drawer;
  bool get _isSourceSelectionVisible => _currentLayer == OverlayLayer.sourceSelection;
  bool get _isSettingPageOpen => _currentLayer == OverlayLayer.settings;
  bool get _isDialogShowing => _currentLayer == OverlayLayer.dialog;
  
  // 统一的层级管理方法
  void _openLayer(OverlayLayer layer) {
    if (layer.index > _currentLayer.index) {  // 只允许打开更高优先级的层
      setState(() {
        _currentLayer = layer;
      });
    }
  }
  
  void _closeLayer() {
    setState(() {
      switch (_currentLayer) {
        case OverlayLayer.dialog:
        case OverlayLayer.settings:
        case OverlayLayer.drawer:
        case OverlayLayer.sourceSelection:
          _currentLayer = OverlayLayer.none;
          break;
        case OverlayLayer.none:
          break;
      }
    });
  }

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
    _openLayer(OverlayLayer.settings);
    
    try {
      final result = await Navigator.push<bool>(
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
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('打开添加源设置页面时发生错误', e, stackTrace); // 捕获并记录页面打开时的错误
      return null;
    } finally {
      _closeLayer();
    }
  }

  // 修改后的返回按键处理逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    LogUtil.v('处理返回事件开始, isProcessingBack: $_isProcessingBack');
    
    if (_isProcessingBack) {
      LogUtil.v('返回事件正在处理中，忽略重复触发');
      return false;
    }
    
    try {
      _isProcessingBack = true;
      LogUtil.v('开始处理返回逻辑, currentLayer: $_currentLayer');
      
      if (_currentLayer != OverlayLayer.none && _currentLayer != OverlayLayer.dialog) {
        _closeLayer();
        return false;
      }

      if (_currentLayer != OverlayLayer.dialog) {
        _openLayer(OverlayLayer.dialog);
        try {
          return await ShowExitConfirm.ExitConfirm(context);
        } finally {
          _closeLayer();
        }
      }
      return false;
    } finally {
      _isProcessingBack = false;
      LogUtil.v('返回事件处理完成');
    }
  }
  
  // 处理选择键逻辑
  Future<void> _handleSelectPress() async {
    // 更新状态
    setState(() {
      _isDatePositionVisible = !_isDatePositionVisible;
      _isShowPauseIcon = widget.isPlaying;
    });

    // 启动计时器控制暂停图标显示时间
    if (widget.isPlaying) {
      _pauseIconTimer?.cancel();
      _pauseIconTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
          _isShowPauseIcon = false; // 3秒后隐藏暂停图标
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
  
  // 修改后的键盘事件处理函数
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return; // 不处理非按键按下事件

    // 处理返回键 - 不使用防抖直接处理
    if (event.logicalKey == LogicalKeyboardKey.goBack) {
      _handleBackPress(context);
      return;
    }

    // 在任何遮罩层显示的情况下，只处理菜单键
    if (hasOverlay) {
      if (event.logicalKey == LogicalKeyboardKey.contextMenu) {
        _handleDebounce(() {
          _closeLayer();
        });
      }
      return; // 在这些状态下，不处理其他任何按键
    }

    // 只有在没有打开任何遮罩层的情况下才处理其他按键
    _handleDebounce(() async {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.contextMenu:
        case LogicalKeyboardKey.arrowRight:
          _openLayer(OverlayLayer.drawer);
          break;
        case LogicalKeyboardKey.arrowLeft:
          await widget.changeChannelSources?.call();
          break;
        case LogicalKeyboardKey.arrowUp:
          _openLayer(OverlayLayer.sourceSelection);
          break;
        case LogicalKeyboardKey.arrowDown:
          widget.controller?.pause();
          await _opensetting();
          break;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          await _handleSelectPress();
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
    _closeLayer(); // 使用统一的关闭层方法
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
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(builder: (context) {
          return RawKeyboardListener(
            focusNode: FocusNode(),
            onKey: _handleKeyEvent,
            child: Container(
              alignment: Alignment.center,
              color: Colors.black,
              child: Stack(
                children: [
                  // 视频初始化且正在播放时，显示视频播放器
                  if (widget.controller!.value.isPlaying) 
                    AspectRatio(
                      aspectRatio: widget.controller!.value.aspectRatio,
                      child: SizedBox(
                        width: double.infinity,
                        child: VideoPlayer(widget.controller!),
                      ),
                    )
                    else 
                      VideoHoldBg(
                        toastString: _drawerIsOpen ? '' : widget.toastString,
                        videoController: widget.controller ?? VideoPlayerController.network(''),
                      ),

                  if (_isDatePositionVisible) const DatePositionWidget(),

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
                        padding: const EdgeInsets.all(20.0),
                        child: Icon(
                          Icons.play_arrow,
                          size: 64,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ),
                  
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
                        onTapChannel: _handleEPGProgramTap,
                        isLandscape: true,
                        onCloseDrawer: () => _closeLayer(),
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
      style: const TextStyle(color: Colors.white, fontSize: 18),
    );
  }
}
