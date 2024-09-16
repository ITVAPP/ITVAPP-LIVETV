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

    // 使用自定义 DateUtil 和 DateFormats 来格式化日期和星期
    String formattedDate = DateUtil.formatDate(
      DateTime.now(), 
      format: locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d
    );

    // 获取星期，支持中文和英文
    String formattedWeekday = DateUtil.getWeekday(
      DateTime.now(), 
      languageCode: locale.startsWith('zh') ? 'zh' : 'en'
    );

    // 使用自定义格式化时间
    String formattedTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');

    return Positioned(
      top: isLandscape ? 20 : 15, // 横屏时距离顶部更远
      right: isLandscape ? 25 : 15, // 横屏时距离右侧更远
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 第一行显示日期和星期
            Text(
              "$formattedDate $formattedWeekday",
              style: TextStyle(
                fontSize: isLandscape ? 22 : 16, // 横屏时日期字体更大
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
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: isLandscape ? 50 : 38, // 横屏时时间字体更大
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
        ),
      ),
    );
  }
}
