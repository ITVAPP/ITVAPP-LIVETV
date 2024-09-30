import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';

class VolumeBrightnessWidget extends StatefulWidget {
  const VolumeBrightnessWidget({super.key});

  @override
  State<VolumeBrightnessWidget> createState() => _VolumeBrightnessWidgetState();
}

class _VolumeBrightnessWidgetState extends State<VolumeBrightnessWidget> {
  double _volume = 0.5;
  double _brightness = 0.5;

  // 1.brightness
  // 2.volume
  int _controlType = 0;
  final double _verticalDragThreshold = 15;  // 提高阈值，避免误触发
  bool _isDragging = false; // 用来标记是否在拖动
  bool _isCooldown = false; // 增加一个冷却标志位

  @override
  void initState() {
    _loadSystemData();
    super.initState();
  }

  _loadSystemData() async {
    try {
      _brightness = (await ScreenBrightness().current).clamp(0.0, 1.0);  // 确保亮度在合理范围
    } catch (e) {
      _brightness = 0.5;  // 如果读取亮度失败，使用默认值
    }

    try {
      _volume = (await FlutterVolumeController.getVolume() ?? 0.5).clamp(0.0, 1.0);  // 确保音量在合理范围
    } catch (e) {
      _volume = 0.5;  // 如果读取音量失败，使用默认值
    }

    await FlutterVolumeController.updateShowSystemUI(false);  // 禁用系统音量UI
    setState(() {});
  }

  @override
  void dispose() {
    FlutterVolumeController.updateShowSystemUI(true);  // 恢复系统音量UI
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度，动态设置调节条的宽度
    double screenWidth = MediaQuery.of(context).size.width;

    // 动态设置宽度为屏幕宽度的 30%
    double containerWidth = screenWidth * 0.3;

    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (DragStartDetails details) {
          // 仅当用户垂直滑动时才处理手势
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx > width / 2) {
            _controlType = 2;  // 右侧调节音量
          } else {
            _controlType = 1;  // 左侧调节亮度
          }
          _isDragging = true; // 开始拖动
          setState(() {});
        },
        onVerticalDragUpdate: (DragUpdateDetails details) {
          // 只处理垂直滑动，忽略水平滑动
          if (details.delta.dy.abs() > _verticalDragThreshold && details.delta.dy.abs() > details.delta.dx.abs()) {
            // 根据滑动速度动态调整步长
            final adjustment = (details.delta.dy / 1000) * (details.primaryDelta ?? 1.0).abs();

            // 即时响应拖动操作，持续调整
            if (_controlType == 2) {
              _volume = (_volume - adjustment).clamp(0.0, 1.0);
              FlutterVolumeController.setVolume(_volume); // 调整音量
            } else {
              _brightness = (_brightness - adjustment).clamp(0.0, 1.0);
              ScreenBrightness().setScreenBrightness(_brightness); // 调整亮度
            }
            setState(() {}); // 更新界面
          }
        },
        onVerticalDragEnd: (DragEndDetails details) {
          _isDragging = false; // 手势结束
          // 增加延迟500毫秒后隐藏调节条，并设置冷却期
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDragging && !_isCooldown) {  // 只有不在拖动时且冷却期结束才隐藏调节条
              _isCooldown = true;  // 进入冷却期
              setState(() {
                _controlType = 0;
              });
              Future.delayed(const Duration(milliseconds: 200), () {
                _isCooldown = false;  // 冷却期结束
              });
            }
          });
        },
        onVerticalDragCancel: () {
          _isDragging = false; // 手势取消
          // 增加延迟500毫秒后隐藏调节条，并设置冷却期
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDragging && !_isCooldown) {  // 只有不在拖动时且冷却期结束才隐藏调节条
              _isCooldown = true;  // 进入冷却期
              setState(() {
                _controlType = 0;
              });
              Future.delayed(const Duration(milliseconds: 200), () {
                _isCooldown = false;  // 冷却期结束
              });
            }
          });
        },
        child: Container(
          alignment: Alignment.topCenter,  // 确保调节条水平居中
          padding: const EdgeInsets.only(top: 10),  // 调节条距离顶部10
          child: _controlType == 0
              ? null
              : Container(
                  width: containerWidth, // 动态宽度
                  height: 28, // 调节条加背景的总高度
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _controlType == 1
                            ? Icons.light_mode
                            : Icons.volume_up_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(
                        width: 5,
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 16,  // 调节条高度
                          child: LinearProgressIndicator(
                            value: _controlType == 1 ? _brightness : _volume,
                            backgroundColor: Colors.white.withOpacity(0.5),
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
