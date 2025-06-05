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
  double _volume = 0.6; // 音量初始值（0.0到1.0）
  double _brightness = 0.6; // 屏幕亮度初始值（0.0到1.0）
  int _volumeLevel = 6; // 音量初始级别（0到10）
  int _brightnessLevel = 6; // 亮度初始级别（0到10）
  final int _maxLevel = 10; // 最大级别常量
  final int _minLevel = 0; // 最小级别常量

  // 滑动控制常量
  final double _dragSensitivity = 30.0; // 触发调节的最小滑动距离
  double _dragDistance = 0.0; // 累计滑动距离

  int _controlType = 0; // 当前调节类型：0无，1亮度，2音量
  bool _isDragging = false; // 是否正在拖动
  bool _isCooldown = false; // 是否处于冷却状态
  AnimationController? _fadeAnimationController; // 调节条显隐动画控制器
  Timer? _hideTimer; // 调节条隐藏定时器

  // 屏幕参数缓存
  double? _screenWidth; // 屏幕宽度
  Orientation? _orientation; // 屏幕方向

  @override
  void initState() {
    super.initState();
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500), // 动画时长500毫秒
      vsync: this, // 绑定动画同步机制
    );
    _loadSystemData(); // 初始化加载系统音量和亮度
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 更新屏幕参数缓存
    _screenWidth = MediaQuery.of(context).size.width;
    _orientation = MediaQuery.of(context).orientation;
  }

  // 异步加载系统音量和亮度数据
  Future<void> _loadSystemData() async {
    try {
      // 优化：移除无效的Future包装，直接设置系统UI
      FlutterVolumeController.showSystemUI = false;
      
      final results = await Future.wait([
        ScreenBrightness().current, // 获取当前屏幕亮度
        FlutterVolumeController.getVolume() ?? Future.value(0.6), // 获取当前音量，默认0.6
      ]);

      // 设置亮度值并限制范围
      _brightness = (results[0] as double).clamp(0.0, 1.0);
      _brightnessLevel = (_brightness * _maxLevel).round();
      
      // 设置音量值并限制范围
      _volume = (results[1] as double).clamp(0.0, 1.0);
      _volumeLevel = (_volume * _maxLevel).round();

      if (mounted) setState(() {}); // 更新界面
    } catch (e) {
      // 出错时使用默认值并记录日志
      _brightness = 0.6;
      _volume = 0.6;
      _volumeLevel = 6;
      _brightnessLevel = 6;
      LogUtil.e('加载系统数据时发生错误：$e');
      if (mounted) setState(() {});
    }
  }

  // 清理资源
  @override
  void dispose() {
    FlutterVolumeController.showSystemUI = true; // 恢复系统音量UI
    _fadeAnimationController?.dispose(); // 释放动画控制器
    _hideTimer?.cancel(); // 取消定时器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根据屏幕方向动态设置调节条宽度
    double containerWidth = _orientation == Orientation.portrait
        ? _screenWidth! * 0.5 // 竖屏宽度占50%
        : _screenWidth! * 0.3; // 横屏宽度占30%

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 垂直拖动开始时确定调节类型
        onVerticalDragStart: (DragStartDetails details) {
          _cancelCooldown(); // 取消冷却状态
          _hideTimer?.cancel(); // 取消隐藏定时器
          final width = _screenWidth!;
          _controlType = details.localPosition.dx > width / 2 ? 2 : 1; // 右侧音量，左侧亮度
          _isDragging = true; // 标记拖动开始
          _fadeAnimationController?.forward(); // 显示调节条
          setState(() {});
        },
        // 拖动时更新级别
        onVerticalDragUpdate: (DragUpdateDetails details) {
          _dragDistance += details.delta.dy;
          if (_dragDistance.abs() >= _dragSensitivity) {
            _changeLevel(_dragDistance < 0 ? 1 : -1); // 上滑加，下滑减
            _dragDistance = 0.0; // 重置滑动距离
          }
        },
        // 优化：合并拖动结束和取消的处理逻辑
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
                        Icon(
                          _controlType == 1 ? Icons.light_mode : Icons.volume_up_outlined, // 亮度或音量图标
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

  // 优化：合并拖动结束处理逻辑
  void _handleDragEnd() {
    _isDragging = false;
    _startCooldown();
    _dragDistance = 0.0;
  }

  // 调整音量或亮度级别
  void _changeLevel(int direction) {
    if (_controlType == 2) {
      _volumeLevel = (_volumeLevel + direction).clamp(_minLevel, _maxLevel); // 更新音量级别
      _updateSystemValue(true); // 更新音量
    } else if (_controlType == 1) {
      _brightnessLevel = (_brightnessLevel + direction).clamp(_minLevel, _maxLevel); // 更新亮度级别
      _updateSystemValue(false); // 更新亮度
    }
  }

  // 优化：合并音量和亮度的更新逻辑
  void _updateSystemValue(bool isVolume) {
    if (isVolume) {
      // 更新音量
      double newVolume = _volumeLevel / _maxLevel;
      if (newVolume != _volume) {
        _volume = newVolume;
        FlutterVolumeController.setVolume(_volume).catchError((e) {
          LogUtil.e('设置音量时发生错误：$e');
        });
        setState(() {});
      }
    } else {
      // 更新亮度
      double newBrightness = _brightnessLevel / _maxLevel;
      if (newBrightness != _brightness) {
        _brightness = newBrightness;
        ScreenBrightness().setScreenBrightness(_brightness).catchError((e) {
          LogUtil.e('设置亮度时发生错误：$e');
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
        _fadeAnimationController?.reverse(); // 隐藏调节条
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _isCooldown = false;
            setState(() => _controlType = 0); // 重置调节类型
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
      _fadeAnimationController?.forward(); // 显示调节条
    }
  }
}
