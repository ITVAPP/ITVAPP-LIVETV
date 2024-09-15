import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 
import 'package:provider/provider.dart'; 
import '../provider/theme_provider.dart';

class DatePositionWidget extends StatelessWidget {
  const DatePositionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 通过 Provider 获取 isTV 的状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    // 获取当前设备的语言环境
    String locale = Localizations.localeOf(context).toLanguageTag();

    // 格式化日期和星期
    String formattedDate = DateFormat('yyyy/MM/dd', locale).format(DateTime.now());
    String formattedWeekday = DateFormat.EEEE(locale).format(DateTime.now());

    // 格式化时间
    String formattedTime = DateFormat('HH:mm', locale).format(DateTime.now());

    return Positioned(
      top: isTV ? 20 : 15, // 电视上距离顶部更远
      right: isTV ? 25 : 15, // 电视上距离右侧更远
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 第一行显示日期和星期
            Text(
              "$formattedDate $formattedWeekday",
              style: TextStyle(
                fontSize: isTV ? 22 : 16, // 电视上日期字体更大
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
                fontSize: isTV ? 50 : 38, // 电视上时间字体更大
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
