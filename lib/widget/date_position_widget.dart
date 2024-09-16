import 'dart:async';  // 引入异步包来支持 Stream
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
      top: isLandscape ? 20 : 15, // 横屏时距离顶部更远
      right: isLandscape ? 25 : 15, // 横屏时距离右侧更远
      child: IgnorePointer(
        child: StreamBuilder<DateTime>(
          stream: timeStream,  // 监听时间流
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container();  // 如果没有数据，返回一个空容器
            }

            // 获取当前的时间
            DateTime currentTime = snapshot.data!;

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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 第一行显示日期和星期
                Text(
                  "$formattedDate $formattedWeekday",
                  style: TextStyle(
                    fontSize: isLandscape ? 19 : 9, // 横屏时日期字体更大
                    color: Colors.white80,
                    shadows: const [
                      Shadow(
                        blurRadius: 8.0,
                        color: Colors.black45,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                // 添加 SizedBox 来调整日期和时间之间的距离
                SizedBox(height: isLandscape ? 3 : 1), // 横屏时增加间距
                // 第二行显示时间
                Text(
                  formattedTime,
                  style: TextStyle(
                    fontSize: isLandscape ? 39 : 29, // 横屏时时间字体更大
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
              ],
            );
          },
        ),
      ),
    );
  }
}
