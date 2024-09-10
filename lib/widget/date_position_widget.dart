import 'package:flutter/material.dart';
import '../util/date_util.dart';
import '../util/env_util.dart';  // 导入 EnvUtil

class DatePositionWidget extends StatelessWidget {
  const DatePositionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 EnvUtil 来判断是否是电视
    bool isTV = EnvUtil.isTV();

    return Positioned(
      top: isTV ? 20 : 12, // 电视上距离顶部更远
      right: isTV ? 20 : 12, // 电视上距离右侧更远
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 第一行显示日期和星期
            Text(
              "${DateUtil.formatDate(DateTime.now(), format: 'yyyy/MM/dd')} ${DateUtil.getWeekday(DateTime.now(), languageCode: 'zh')}",
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
              DateUtil.formatDate(DateTime.now(), format: 'HH:mm'),
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
