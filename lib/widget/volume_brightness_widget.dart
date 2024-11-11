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
  int _volumeLevel = 5;  // 音量的初始级别（10级制，0到10）
  int _brightnessLevel = 5;  // 亮度的初始级别（10级制，0到10）
  final int _maxLevel = 10;  // 最大级别为10级
  final int _minLevel = 0;  // 最低级别为0

  // 滑动相关的常量
  final double _dragSensitivity = 30.0;  // 触发调节的最小滑动距离
  double _dragDistance = 0.0;  // 累积滑动距离

  // 1：亮度 2：音量，用于确定当前调节的类型
  int _controlType = 0;
  bool _isDragging = false;  // 标记是否在拖动过程中
  bool _isCooldown = false;  // 冷却标志位，控制调节条动画的冷却状态
  AnimationController? _fadeAnimationController;  // 动画控制器，用于调节条的显隐动画
  Timer? _hideTimer;  // 定时器，用于控制调节条隐藏的时间

  @override
  void initState() {
    super.initState();
    _loadSystemData();  // 加载系统当前的音量和亮度
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),  // 动画时长
      vsync: this,  // 绑定动画控制器
    );
  }

  // 异步加载系统的音量和亮度数据
  Future<void> _loadSystemData() async {
    try {
      // 获取当前亮度并转换为10级制
      _brightness = (await ScreenBrightness().current).clamp(0.0, 1.0);
      _brightnessLevel = (_brightness * _maxLevel).round();
    } catch (e) {
      _brightness = 0.5;  // 获取失败时使用默认亮度
      _brightnessLevel = 5;
      LogUtil.e('读取亮度时发生错误：$e');
    }

    try {
      // 获取当前音量并转换为10级制
      _volume = ((await FlutterVolumeController.getVolume()) ?? 0.5).clamp(0.0, 1.0) as double;
      _volumeLevel = (_volume * _maxLevel).round();
    } catch (e) {
      _volume = 0.5;  // 获取失败时使用默认音量
      _volumeLevel = 5;
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
    _hideTimer?.cancel();  // 释放定时器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;  // 获取屏幕的宽度
    Orientation orientation = MediaQuery.of(context).orientation;  // 获取当前屏幕方向

    // 根据屏幕方向设置调节条宽度
    double containerWidth;
    if (orientation == Orientation.portrait) {
      containerWidth = screenWidth * 0.5;  // 竖屏时调节条宽度
    } else {
      containerWidth = screenWidth * 0.3;  // 横屏时调节条宽度
    }

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 手指按下时，确定是调节音量还是亮度
        onVerticalDragStart: (DragStartDetails details) {
          _cancelCooldown();  // 取消冷却动画，保持调节条可见
          _hideTimer?.cancel();  // 取消隐藏定时器，避免过早隐藏

          final width = MediaQuery.of(context).size.width;
          _controlType = details.localPosition.dx > width / 2 ? 2 : 1;  // 右侧控制音量，左侧控制亮度
          _isDragging = true;  // 标记为正在拖动
          _fadeAnimationController?.forward();  // 启动调节条显示动画
          setState(() {});  // 更新界面
        },
        // 手指拖动时，实时更新音量或亮度
        onVerticalDragUpdate: (DragUpdateDetails details) {
          _dragDistance += details.delta.dy;

          // 只有滑动超过灵敏度时才增加或减少级别
          if (_dragDistance.abs() >= _dragSensitivity) {
            if (_dragDistance < 0) {
              _increaseLevel();  // 上滑增加一级
            } else if (_dragDistance > 0) {
              _decreaseLevel();  // 下滑减少一级
            }
            _dragDistance = 0.0;  // 重置累计滑动距离
          }
        },
        // 手势结束时，触发调节条的冷却动画
        onVerticalDragEnd: (DragEndDetails details) {
          _isDragging = false;  // 结束拖动
          _startCooldown();  // 启动冷却倒计时
          _dragDistance = 0.0;  // 重置累计滑动距离
        },
        // 手势取消时，触发冷却动画
        onVerticalDragCancel: () {
          _isDragging = false;  // 取消拖动
          _startCooldown();  // 启动冷却倒计时
          _dragDistance = 0.0;  // 重置累计滑动距离
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
                    width: containerWidth,  // 使用动态设置的调节条宽度
                    height: 32,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),  // 半透明背景
                      borderRadius: BorderRadius.circular(12),  // 圆角矩形
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _controlType == 1 ? Icons.light_mode : Icons.volume_up_outlined,  // 图标根据类型显示
                          color: Colors.white,
                          size: 18,  // 修改图标尺寸为18
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: SizedBox(
                            height: 20,  // 修改进度条容器高度为20
                            child: LinearProgressIndicator(
                              value: _controlType == 1
                                  ? _brightnessLevel / _maxLevel  // 显示当前亮度进度
                                  : _volumeLevel / _maxLevel,  // 显示当前音量进度
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

  // 调节音量或亮度增加一级
  void _increaseLevel() {
    if (_controlType == 2) {
      _volumeLevel = (_volumeLevel + 1).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
      _updateVolume();
    } else if (_controlType == 1) {
      _brightnessLevel = (_brightnessLevel + 1).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
      _updateBrightness();
    }
  }

  // 调节音量或亮度减少一级
  void _decreaseLevel() {
    if (_controlType == 2) {
      _volumeLevel = (_volumeLevel - 1).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
      _updateVolume();
    } else if (_controlType == 1) {
      _brightnessLevel = (_brightnessLevel - 1).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
      _updateBrightness();
    }
  }

  // 更新音量
  void _updateVolume() {
    double newVolume = _volumeLevel / _maxLevel;  // 将等级转换为0-1之间的值
    if (newVolume != _volume) {
      _volume = newVolume;
      FlutterVolumeController.setVolume(_volume).catchError((e) {
        LogUtil.e('设置音量时发生错误：$e');
      });
      setState(() {});  // 更新界面
    }
  }

  // 更新亮度
  void _updateBrightness() {
    double newBrightness = _brightnessLevel / _maxLevel;  // 将等级转换为0-1之间的值
    if (newBrightness != _brightness) {
      _brightness = newBrightness;
      ScreenBrightness().setScreenBrightness(_brightness).catchError((e) {
        LogUtil.e('设置亮度时发生错误：$e');
      });
      setState(() {});  // 更新界面
    }
  }

  // 冷却期触发逻辑封装，当手指离开后触发冷却期，隐藏调节条
  void _startCooldown() {
    _hideTimer?.cancel();  // 取消之前的定时器，避免多次调用
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDragging && !_isCooldown) {
        _isCooldown = true;  // 进入冷却期
        _fadeAnimationController?.reverse();  // 启动隐藏调节条的动画
        Future.delayed(const Duration(milliseconds: 500), () {
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
    if (_isCooldown) {  // 只有在冷却期时才取消隐藏定时器
      _hideTimer?.cancel();  // 取消隐藏定时器
      _isCooldown = false;  // 取消冷却状态
      _fadeAnimationController?.forward();  // 启动显示调节条的动画
    }
  }
}
