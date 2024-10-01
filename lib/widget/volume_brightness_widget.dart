import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class VolumeBrightnessWidget extends StatefulWidget {
  const VolumeBrightnessWidget({super.key});

  @override
  State<VolumeBrightnessWidget> createState() => _VolumeBrightnessWidgetState();
}

class _VolumeBrightnessWidgetState extends State<VolumeBrightnessWidget> with SingleTickerProviderStateMixin {
  double _volume = 0.5;  // 音量初始值，范围 0.0 - 1.0
  double _brightness = 0.5;  // 屏幕亮度初始值，范围 0.0 - 1.0
  double _tempVolume = 0.5;  // 临时音量值，用于手动调节
  double _tempBrightness = 0.5;  // 临时亮度值，用于手动调节

  // 1：亮度 2：音量，用于确定当前调节的类型
  int _controlType = 0;
  final double _verticalDragThreshold = 10;  // 手势拖动的阈值，避免误触发
  bool _isDragging = false;  // 标记是否在拖动过程中
  bool _isCooldown = false;  // 冷却标志位，控制调节条动画的冷却状态
  AnimationController? _fadeAnimationController;  // 动画控制器，用于调节条的显隐动画

  @override
  void initState() {
    super.initState();
    _loadSystemData();  // 加载系统当前的音量和亮度
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),  // 动画时长
      vsync: this,  // 绑定动画控制器
    );
  }

  // 异步加载系统的音量和亮度数据
  Future<void> _loadSystemData() async {
    try {
      _brightness = (await ScreenBrightness().current).clamp(0.0, 1.0);  // 获取当前亮度并限制范围
      _tempBrightness = _brightness;  // 更新临时亮度值
    } catch (e) {
      _brightness = 0.5;  // 获取失败时使用默认亮度
      LogUtil.e('读取亮度时发生错误：$e');
    }

    try {
      _volume = ((await FlutterVolumeController.getVolume()) ?? 0.5).clamp(0.0, 1.0) as double;  // 获取当前音量并限制范围
      _tempVolume = _volume;  // 更新临时音量值
    } catch (e) {
      _volume = 0.5;  // 获取失败时使用默认音量
      LogUtil.e('读取音量时发生错误：$e');
    }

    try {
      FlutterVolumeController.showSystemUI = false;  // 隐藏系统默认的音量UI
    } catch (e) {
      LogUtil.e('禁用系统音量UI时发生错误：$e');
    }

    if (mounted) setState(() {});  // 更新界面
  }

  // 组件销毁时，恢复系统音量UI并释放动画控制器
  @override
  void dispose() {
    FlutterVolumeController.showSystemUI = true;  // 恢复系统音量UI
    _fadeAnimationController?.dispose();  // 释放动画控制器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;  // 获取屏幕的宽度
    double playerHeight = MediaQuery.of(context).size.height * 0.5;  // 假设播放器占屏幕高度的50%，你可以动态调整

    double containerWidth = screenWidth * 0.3;  // 动态设置调节条宽度为屏幕宽度的30%

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 手指按下时，确定是调节音量还是亮度
        onVerticalDragStart: (DragStartDetails details) {
          _cancelCooldown();  // 取消冷却动画，保持调节条可见

          final width = MediaQuery.of(context).size.width;
          // **保持左侧调节亮度，右侧调节音量的逻辑**
          _controlType = details.localPosition.dx > width / 2 ? 2 : 1;  // 右侧控制音量，左侧控制亮度
          _isDragging = true;  // 标记为正在拖动
          _fadeAnimationController?.forward();  // 启动调节条显示动画
          setState(() {});  // 更新界面
        },
        // 手指拖动时，实时更新音量或亮度
        onVerticalDragUpdate: (DragUpdateDetails details) {
          if (details.delta.dy.abs() > _verticalDragThreshold) {
            _isDragging = true;  // 标记为正在拖动

            // 计算滑动的比例变化：滑动的dy相对播放器高度的百分比
            double relativeDragChange = details.delta.dy / playerHeight;

            // 实时更新音量或亮度
            if (_controlType == 2) {
              // 音量变化，根据滑动的相对距离进行变化
              _tempVolume = (_tempVolume - relativeDragChange).clamp(0.0, 1.0);  // 下滑减少音量
              FlutterVolumeController.setVolume(_tempVolume).catchError((e) {
                LogUtil.e('设置音量时发生错误：$e');
              });
              setState(() {
                _volume = _tempVolume;  // 更新音量UI
              });
            } else {
              // 亮度变化，根据滑动的相对距离进行变化
              _tempBrightness = (_tempBrightness - relativeDragChange).clamp(0.0, 1.0);  // 下滑减少亮度
              ScreenBrightness().setScreenBrightness(_tempBrightness).catchError((e) {
                LogUtil.e('设置亮度时发生错误：$e');
              });
              setState(() {
                _brightness = _tempBrightness;  // 更新亮度UI
              });
            }
          }
        },
        // 手势结束时，触发调节条的冷却动画
        onVerticalDragEnd: (DragEndDetails details) {
          _isDragging = false;  // 结束拖动
          _triggerCooldown();  // 启动冷却动画
        },
        // 手势取消时，触发冷却动画
        onVerticalDragCancel: () {
          _isDragging = false;  // 取消拖动
          _triggerCooldown();  // 启动冷却动画
        },
        child: FadeTransition(
          opacity: _fadeAnimationController!,  // 控制调节条的显隐动画
          child: Container(
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            // 根据当前控制类型显示音量或亮度调节条
            child: _controlType == 0
                ? null
                : Container(
                    width: containerWidth,
                    height: 28,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),  // 半透明背景
                      borderRadius: BorderRadius.circular(15),  // 圆角矩形
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _controlType == 1 ? Icons.light_mode : Icons.volume_up_outlined,  // 图标根据类型显示
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: SizedBox(
                            height: 16,
                            child: LinearProgressIndicator(
                              value: _controlType == 1 ? _brightness : _volume,  // 显示当前亮度或音量
                              backgroundColor: Colors.white.withOpacity(0.5),  // 背景条
                              color: Colors.redAccent,  // 进度条颜色
                              borderRadius: BorderRadius.circular(10),  // 圆角进度条
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // 冷却期触发逻辑封装，当手指离开后触发冷却期，隐藏调节条
  void _triggerCooldown() {
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!_isDragging && !_isCooldown) {
        _isCooldown = true;  // 进入冷却期
        _fadeAnimationController?.reverse();  // 启动隐藏调节条的动画
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _isCooldown = false;  // 冷却期结束
            setState(() {
              _controlType = 0;  // 重置调节类型
            });
          }
        });
      }
    });
  }

  // 取消冷却期逻辑，手指按下时取消调节条的隐藏
  void _cancelCooldown() {
    _isCooldown = false;  // 取消冷却状态
    _fadeAnimationController?.forward();  // 启动显示调节条的动画
  }
}
