import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:itvapp_live_tv/util/log_util.dart';  // 导入 LogUtil

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

  @override
  void initState() {
    LogUtil.safeExecute(() async {
      _loadSystemData();  // 加载系统数据
    }, '初始化加载系统数据时出错');
    super.initState();
  }

  _loadSystemData() async {
    LogUtil.safeExecute(() async {
      _brightness = await ScreenBrightness().current;  // 获取当前屏幕亮度
      _volume = await FlutterVolumeController.getVolume() ?? 0.5;  // 获取当前音量
      await FlutterVolumeController.updateShowSystemUI(false);  // 隐藏系统音量 UI
      setState(() {});  // 更新 UI
    }, '加载系统亮度和音量数据时出错');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(44),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (DragStartDetails details) {
          LogUtil.safeExecute(() {
            final width = MediaQuery.of(context).size.width;
            if (details.localPosition.dx > width / 2) {
              _controlType = 2;  // 控制音量
            } else {
              _controlType = 1;  // 控制亮度
            }
          }, '垂直拖动开始时出错');
        },
        onVerticalDragUpdate: (DragUpdateDetails details) {
          LogUtil.safeExecute(() {
            if (_controlType == 2) {
              _volume = (_volume + (-details.delta.dy / 500)).clamp(0.0, 1.0);
              FlutterVolumeController.setVolume(_volume);  // 设置音量
            } else {
              _brightness = (_brightness + (-details.delta.dy / 500)).clamp(0.0, 1.0);
              ScreenBrightness().setScreenBrightness(_brightness);  // 设置亮度
            }
            setState(() {});  // 更新 UI
          }, '垂直拖动更新时出错');
        },
        onVerticalDragEnd: (DragEndDetails details) {
          LogUtil.safeExecute(() {
            setState(() {
              _controlType = 0;  // 重置控制类型
            });
          }, '垂直拖动结束时出错');
        },
        onVerticalDragCancel: () {
          LogUtil.safeExecute(() {
            setState(() {
              _controlType = 0;  // 取消拖动时重置控制类型
            });
          }, '垂直拖动取消时出错');
        },
        child: Container(
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 20),
          child: _controlType == 0
              ? null
              : Container(
                  width: 150,
                  height: 30,
                  padding:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
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
                        child: LinearProgressIndicator(
                          value: _controlType == 1 ? _brightness : _volume,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      )
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
