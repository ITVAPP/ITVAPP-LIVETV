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
  double _volume = 0.6;  // 音量初始值，范围 0.0 - 1.0
  double _brightness = 0.6;  // 屏幕亮度初始值，范围 0.0 - 1.0
  int _volumeLevel = 6;  // 音量的初始级别（10级制，0到10）
  int _brightnessLevel = 6;  // 亮度的初始级别（10级制，0到10）
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

  // 缓存屏幕参数
  double? _screenWidth;
  Orientation? _orientation;

  @override
  void initState() {
    super.initState();
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),  // 动画时长
      vsync: this,  // 绑定动画控制器
    );
    _loadSystemData();  // 加载系统当前的音量和亮度
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 更新缓存的屏幕参数
    _screenWidth = MediaQuery.of(context).size.width;
    _orientation = MediaQuery.of(context).orientation;
  }

  // 异步加载系统的音量和亮度数据，使用 Future.wait 批量处理
  Future<void> _loadSystemData() async {
    try {
      // 批量获取音量和亮度
      final results = await Future.wait([
        ScreenBrightness().current,
        FlutterVolumeController.getVolume() ?? Future.value(0.6),
        Future(() => FlutterVolumeController.showSystemUI = false),
      ]);

      // 处理亮度
      _brightness = (results[0] as double).clamp(0.0, 1.0);
      _brightnessLevel = (_brightness * _maxLevel).round();

      // 处理音量
      _volume = (results[1] as double).clamp(0.0, 1.0);
      _volumeLevel = (_volume * _maxLevel).round();

      // 仅在 mounted 时更新状态
      if (mounted) setState(() {});
    } catch (e) {
      // 默认值和错误日志
      _brightness = 0.6computationally expensive
      _volume = 0.6;
      _volumeLevel = 6;
      _brightnessLevel = 6;
      LogUtil.e('加载系统数据时发生错误：$e');
      if (mounted) setState(() {});
    }
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
    // 使用缓存的屏幕宽度和方向
    double containerWidth = _orientation == Orientation.portrait
        ? _screenWidth! * 0.5  // 竖屏时调节条宽度
        : _screenWidth! * 0.3;  // 横屏时调节条宽度

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 手指按下时，确定是调节音量还是亮度
        onVerticalDragStart: (DragStartDetails details) {
          _cancelCooldown();  // 取消冷却动画，保持调节条可见
          _hideTimer?.cancel();  // 取消隐藏定时器，避免过早隐藏

          final width = _screenWidth!;
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
              _changeLevel(1);  // 上滑增加一级
            } else if (_dragDistance > 0) {
              _changeLevel(-1);  // 下滑减少一级
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

  // 统一调节级别的方法，direction 为 1（增加）或 -1（减少）
  void _changeLevel(int direction) {
    if (_controlType == 2) {
      _volumeLevel = (_volumeLevel + direction).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
      _updateVolume();
    } else if (_controlType == 1) {
      _brightnessLevel = (_brightnessLevel + direction).clamp(_minLevel, _maxLevel);  // 确保级别在0到10之间
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
      if (!_isDragging && !_isCooldown && _fadeAnimationController?.isCompleted == true) {
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
    if (_isCooldown && _fadeAnimationController?.isDismissed == true) {  // 只有在冷却期且动画已隐藏时才取消
      _hideTimer?.cancel();  // 取消隐藏定时器
      _isCooldown = false;  // 取消冷却状态
      _fadeAnimationController?.forward();  // 启动显示调节条的动画
    }
  }
}
