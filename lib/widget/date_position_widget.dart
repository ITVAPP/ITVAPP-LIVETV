import 'dart:async'; 
import 'package:flutter/material.dart';
import '../util/date_util.dart'; 

class DatePositionWidget extends StatelessWidget {
  const DatePositionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 MediaQuery 判断设备是否为横屏
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 获取当前设备的语言环境
    String locale = Localizations.localeOf(context).toLanguageTag();
    // 创建一个时间流，每3秒更新一次
    Stream<DateTime> timeStream = Stream.periodic(
      const Duration(seconds: 3), 
      (_) => DateTime.now(),
    );
    return Positioned(
      top: isLandscape ? 18 : 12, // 横屏时距离顶部更远
      right: isLandscape ? 22 : 12, // 横屏时距离右侧更远
      child: IgnorePointer(
        child: StreamBuilder<DateTime>(
          stream: timeStream,  // 监听时间流
          builder: (context, snapshot) {
            // 获取当前的时间，如果 snapshot 中没有数据，则使用当前时间
            DateTime currentTime = snapshot.data ?? DateTime.now();
            // 使用自定义 DateUtil 和 DateFormats 来格式化日期和星期
            String formattedDate = DateUtil.formatDate(
              currentTime, 
              format: locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d,
            );
            // 获取星期，支持中文和英文
            String formattedWeekday = DateUtil.getWeekday(
              currentTime, 
              languageCode: locale.startsWith('zh') ? 'zh' : 'en',
            );
            // 使用自定义格式化时间
            String formattedTime = DateUtil.formatDate(currentTime, format: 'HH:mm');
            return Stack(
              clipBehavior: Clip.none, // 允许子组件超出Stack边界
              children: [
                // 第一行显示日期和星期
                Text(
                  "$formattedDate $formattedWeekday",
                  style: TextStyle(
                    fontSize: isLandscape ? 16 : 8, // 横屏时日期字体更大
                    color: Colors.white70,
                    shadows: const [
                      Shadow(
                        blurRadius: 8.0,
                        color: Colors.black45,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                // 第二行显示时间
                Positioned(
                  top: isLandscape ? 18 : 9, // 控制日期和时间之间的间距
                  right: 0, // 右对齐
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: isLandscape ? 38 : 28, // 横屏时时间字体更大
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        Shadow(
                          blurRadius: 10.0, // 模糊效果
                          color: Colors.black,
                          offset: Offset(0, 2),
                        ),
                      ],
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
