import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// 音量与亮度调节组件
class VolumeBrightnessWidget extends StatefulWidget {
  const VolumeBrightnessWidget({super.key});
  @override
  State<VolumeBrightnessWidget> createState() => _VolumeBrightnessWidgetState();
}

class _VolumeBrightnessWidgetState extends State<VolumeBrightnessWidget> with SingleTickerProviderStateMixin {
  // 音量初始值，0.0到1.0
  double _volume = 0.6;
  // 亮度初始值，0.0到1.0
  double _brightness = 0.6;
  // 音量初始级别，0到10
  int _volumeLevel = 6;
  // 亮度初始级别，0到10
  int _brightnessLevel = 6;
  // 最大级别常量
  final int _maxLevel = 10;
  // 最小级别常量
  final int _minLevel = 0;
  // 触发调节的最小滑动距离
  final double _dragSensitivity = 30.0;
  // 累计滑动距离
  double _dragDistance = 0.0;
  // 当前调节类型：0无，1亮度，2音量
  int _controlType = 0;
  // 是否正在拖动
  bool _isDragging = false;
  // 是否处于冷却状态
  bool _isCooldown = false;
  // 调节条显隐动画控制器
  AnimationController? _fadeAnimationController;
  // 调节条隐藏定时器
  Timer? _hideTimer;
  // 屏幕宽度缓存
  double? _screenWidth;
  // 屏幕方向缓存
  Orientation? _orientation;

  @override
  void initState() {
    super.initState();
    // 初始化动画控制器，时长500毫秒
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    // 加载系统音量和亮度
    _loadSystemData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 更新屏幕宽度和方向
    _screenWidth = MediaQuery.of(context).size.width;
    _orientation = MediaQuery.of(context).orientation;
  }

  // 加载系统音量和亮度
  Future<void> _loadSystemData() async {
    try {
      // 隐藏系统音量UI
      FlutterVolumeController.showSystemUI = false;
      final results = await Future.wait([
        ScreenBrightness().current, // 获取当前屏幕亮度
        FlutterVolumeController.getVolume() ?? Future.value(0.6), // 获取当前音量，默认0.6
      ]);

      // 设置亮度并限制范围
      _brightness = (results[0] as double).clamp(0.0, 1.0);
      _brightnessLevel = (_brightness * _maxLevel).round();
      // 设置音量并限制范围
      _volume = (results[1] as double).clamp(0.0, 1.0);
      _volumeLevel = (_volume * _maxLevel).round();

      if (mounted) setState(() {}); // 更新界面
    } catch (e) {
      // 使用默认值并记录异常
      _brightness = 0.6;
      _volume = 0.6;
      _volumeLevel = 6;
      _brightnessLevel = 6;
      LogUtil.e('加载音量和亮度数据异常: $e'); // 记录加载音量和亮度异常
      if (mounted) setState(() {});
    }
  }

  // 清理资源
  @override
  void dispose() {
    // 恢复系统音量UI
    FlutterVolumeController.showSystemUI = true;
    // 释放动画控制器
    _fadeAnimationController?.dispose();
    // 取消隐藏定时器
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根据屏幕方向设置调节条宽度
    double containerWidth = _orientation == Orientation.portrait
        ? _screenWidth! * 0.5 // 竖屏宽度占50%
        : _screenWidth! * 0.3; // 横屏宽度占30%

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 垂直拖动开始，确定调节类型
        onVerticalDragStart: (DragStartDetails details) {
          // 取消冷却状态
          _cancelCooldown();
          // 取消隐藏定时器
          _hideTimer?.cancel();
          final width = _screenWidth!;
          // 右侧调节音量，左侧调节亮度
          _controlType = details.localPosition.dx > width / 2 ? 2 : 1;
          _isDragging = true;
          // 显示调节条
          _fadeAnimationController?.forward();
          setState(() {});
        },
        // 拖动更新级别
        onVerticalDragUpdate: (DragUpdateDetails details) {
          _dragDistance += details.delta.dy;
          if (_dragDistance.abs() >= _dragSensitivity) {
            // 上滑增加级别，下滑减少级别
            _changeLevel(_dragDistance < 0 ? 1 : -1);
            _dragDistance = 0.0; // 重置滑动距离
          }
        },
        // 拖动结束或取消
        onVerticalDragEnd: (_) => _handleDragEnd(),
        onVerticalDragCancel: _handleDragEnd,
        child: FadeTransition(
          opacity: _fadeAnimationController!, // 调节条淡入淡出动画
          child: Container(
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            child: _controlType == 0
                ? null
                : Container(
                    width: containerWidth, // 动态调节条宽度
                    height: 32,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5), // 半透明背景
                      borderRadius: BorderRadius.circular(12), // 圆角设计
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 显示亮度或音量图标
                        Icon(
                          _controlType == 1 ? Icons.light_mode : Icons.volume_up_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: SizedBox(
                            height: 20,
                            child: LinearProgressIndicator(
                              value: _controlType == 1
                                  ? _brightnessLevel / _maxLevel // 亮度进度
                                  : _volumeLevel / _maxLevel, // 音量进度
                              backgroundColor: Colors.white.withOpacity(0.5), // 背景条颜色
                              color: Colors.redAccent, // 进度条颜色
                              borderRadius: BorderRadius.circular(10), // 圆角进度条
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

  // 处理拖动结束
  void _handleDragEnd() {
    _isDragging = false;
    // 启动冷却倒计时
    _startCooldown();
    // 重置滑动距离
    _dragDistance = 0.0;
  }

  // 调整音量或亮度级别
  void _changeLevel(int direction) {
    if (_controlType == 2) {
      // 更新音量级别并限制范围
      _volumeLevel = (_volumeLevel + direction).clamp(_minLevel, _maxLevel);
      // 更新系统音量
      _updateSystemenskap true);
    } else if (_controlType == 1) {
      // 更新亮度级别并限制范围
      _brightnessLevel = (_brightnessLevel + direction).clamp(_minLevel, _maxLevel);
      // 更新系统亮度
      _updateSystemValue(false);
    }
  }

  // 更新系统音量或亮度
  void _updateSystemValue(bool isVolume) {
    if (isVolume) {
      double newVolume = _volumeLevel / _maxLevel;
      if (newVolume != _volume) {
        _volume = newVolume;
        // 设置系统音量
        FlutterVolumeController.setVolume(_volume).catchError((e) {
          LogUtil.e('音量调节异常: $e'); // 记录音量调节异常
        });
        setState(() {});
      }
    } else {
      double newBrightness = _brightnessLevel / _maxLevel;
      if (newBrightness != _brightness) {
        _brightness = newBrightness;
        // 设置系统亮度
        ScreenBrightness().setScreenBrightness(_brightness).catchError((e) {
          LogUtil.e('亮度调节异常: $e'); // 记录亮度调节异常
        });
        setState(() {});
      }
    }
  }

  // 启动冷却倒计时，2秒后隐藏调节条
  void _startCooldown() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDragging && !_isCooldown && _fadeAnimationController?.isCompleted == true) {
        _isCooldown = true;
        // 隐藏调节条
        _fadeAnimationController?.reverse();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _isCooldown = false;
            // 重置调节类型
            setState(() => _controlType = 0);
          }
        });
      }
    });
  }

  // 取消冷却状态，保持调节条可见
  void _cancelCooldown() {
    if (_isCooldown && _fadeAnimationController?.isDismissed == true) {
      _hideTimer?.cancel();
      _isCooldown = false;
      // 显示调节条
      _fadeAnimationController?.forward();
    }
  }
}
