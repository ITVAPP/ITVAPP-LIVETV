import 'dart:async';
import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/date_util.dart';

class DatePositionWidget extends StatefulWidget {
  const DatePositionWidget({super.key});

  @override
  State<DatePositionWidget> createState() => _DatePositionWidgetState();
}

class _DatePositionWidgetState extends State<DatePositionWidget> {
  late final Stream<DateTime> _timeStream; // 时间流
  StreamSubscription<DateTime>? _timeSubscription; // 管理时间流订阅，防止内存泄漏
  
  // 文字阴影效果，提升文本视觉层次感
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: 3.0, // 模糊半径
      color: Colors.black, // 阴影颜色
      offset: Offset(0, 1), // 阴影偏移量
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 初始化时间流，每20秒更新一次
    _timeStream = Stream.periodic(
      const Duration(seconds: 20),
      (_) => DateTime.now(),
    );
    // 订阅时间流，便于后续清理
    _timeSubscription = _timeStream.listen((_) {});
  }

  @override
  void dispose() {
    // 取消时间流订阅，释放资源
    _timeSubscription?.cancel();
    super.dispose();
  }

  // 判断设备是否为横屏模式
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  // 获取当前语言环境，用于时间格式化
  String _getLocale(BuildContext context) {
    return Localizations.localeOf(context).toLanguageTag();
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = _isLandscape(context); // 当前是否为横屏
    String locale = _getLocale(context); // 当前语言环境

    return Positioned(
      top: isLandscape ? 12 : 8, // 动态调整垂直位置
      right: isLandscape ? 16 : 6, // 动态调整水平位置
      child: IgnorePointer(
        // 使用 StreamBuilder 实时更新时间显示
        child: StreamBuilder<DateTime>(
          stream: _timeStream,
          builder: (context, snapshot) {
            // 获取当前时间，优先使用快照数据
            DateTime currentTime = snapshot.data ?? DateTime.now();
            
            // 格式化日期，适配中英文环境
            String formattedDate = DateUtil.formatDate(
              currentTime,
              format: locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d,
            );
            // 获取星期，适配中英文格式
            String formattedWeekday = DateUtil.getWeekday(
              currentTime,
              languageCode: locale.startsWith('zh') ? 'zh' : 'en',
            );
            // 格式化时间为 HH:mm
            String formattedTime = DateUtil.formatDate(currentTime, format: 'HH:mm');

            return Stack(
              clipBehavior: Clip.none, // 允许内容超出边界
              children: [
                // 显示日期和星期
                Text(
                  "$formattedDate $formattedWeekday",
                  style: TextStyle(
                    fontSize: isLandscape ? 16 : 8, // 动态调整字体大小
                    color: Colors.white, // 白色字体
                    fontWeight: FontWeight.bold, // 粗体
                    shadows: _textShadows, // 添加阴影效果
                  ),
                ),
                // 显示时间，位于下方
                Positioned(
                  top: isLandscape ? 18 : 12, // 动态调整垂直位置
                  right: 0,
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: isLandscape ? 38 : 28, // 动态调整字体大小
                      color: Colors.white, // 白色字体
                      fontWeight: FontWeight.bold, // 粗体
                      shadows: _textShadows, // 添加阴影效果
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
