import 'dart:async';
import 'package:flutter/material.dart';
import '../util/date_util.dart';

class DatePositionWidget extends StatefulWidget {
  const DatePositionWidget({super.key});

  @override
  State<DatePositionWidget> createState() => _DatePositionWidgetState();
}

class _DatePositionWidgetState extends State<DatePositionWidget> {
  late final Stream<DateTime> _timeStream;
  
  // 定义文字阴影效果，用于提升文本的视觉层次感
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: 3.0, // 模糊半径
      color: Colors.black, // 阴影颜色
      offset: Offset(0, 1), // 阴影偏移
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 每3秒生成一个新的当前时间，构成时间流
    _timeStream = Stream.periodic(
      const Duration(seconds: 3),
      (_) => DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 判断当前设备的方向，横屏为 true，竖屏为 false
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 获取当前的语言环境，用于时间格式化
    String locale = Localizations.localeOf(context).toLanguageTag();

    return Positioned(
      // 根据屏幕方向动态调整组件的垂直位置
      top: isLandscape ? 12 : 8,
      // 根据屏幕方向动态调整组件的水平位置
      right: isLandscape ? 16 : 6,
      child: IgnorePointer(
        // 使用 StreamBuilder 监听时间流，实时更新日期和时间显示
        child: StreamBuilder<DateTime>(
          stream: _timeStream,
          builder: (context, snapshot) {
            // 获取当前时间，如果流中数据为空，则使用系统当前时间
            DateTime currentTime = snapshot.data ?? DateTime.now();
            
            // 根据语言环境格式化日期（中文格式与其他语言格式不同）
            String formattedDate = DateUtil.formatDate(
              currentTime,
              format: locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d,
            );
            // 获取星期信息，中文与英文的格式化逻辑不同
            String formattedWeekday = DateUtil.getWeekday(
              currentTime,
              languageCode: locale.startsWith('zh') ? 'zh' : 'en',
            );
            // 格式化时间为小时和分钟显示
            String formattedTime = DateUtil.formatDate(currentTime, format: 'HH:mm');

            return Stack(
              clipBehavior: Clip.none, // 允许超出父组件范围的绘制
              children: [
                // 显示日期和星期信息
                Text(
                  "$formattedDate $formattedWeekday",
                  style: TextStyle(
                    fontSize: isLandscape ? 16 : 8, // 根据屏幕方向调整字体大小
                    color: Colors.white, // 白色字体
                    fontWeight: FontWeight.bold, // 粗体字体
                    shadows: _textShadows, // 应用阴影效果
                  ),
                ),
                // 显示时间，位于日期和星期的下方
                Positioned(
                  top: isLandscape ? 18 : 12, // 根据屏幕方向调整垂直位置
                  right: 0,
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: isLandscape ? 38 : 28, // 根据屏幕方向调整字体大小
                      color: Colors.white, // 白色字体
                      fontWeight: FontWeight.bold, // 粗体字体
                      shadows: _textShadows, // 应用阴影效果
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
