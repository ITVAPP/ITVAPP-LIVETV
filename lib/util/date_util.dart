/// 日期时间工具类
class DateFormats {
  static const String full = 'yyyy-MM-dd HH:mm:ss';  // 完整日期时间
  static const String y_mo_d_h_m = 'yyyy-MM-dd HH:mm';  // 年月日时分
  static const String y_mo_d = 'yyyy-MM-dd';  // 年月日
  static const String y_mo = 'yyyy-MM';  // 年月
  static const String mo_d = 'MM-dd';  // 月日
  static const String mo_d_h_m = 'MM-dd HH:mm';  // 月日时分
  static const String h_m_s = 'HH:mm:ss';  // 时分秒
  static const String h_m = 'HH:mm';  // 时分

  static const String zh_full = 'yyyy年MM月dd日 HH:mm:ss';  // 中文完整日期时间
  static const String zh_y_mo_d_h_m = 'yyyy年MM月dd日 HH:mm';  // 中文年月日时分
  static const String zh_y_mo_d = 'yyyy年MM月dd日';  // 中文年月日
  static const String zh_y_mo = 'yyyy年MM月';  // 中文年月
  static const String zh_mo_d = 'MM月dd日';  // 中文月日
  static const String zh_mo_d_h_m = 'MM月dd日 HH:mm';  // 中文月日时分
  static const String zh_h_m_s = 'HH:mm:ss';  // 中文时分秒
  static const String zh_h_m = 'HH:mm';  // 中文时分
}

/// 月份天数映射，闰年动态处理
const Map<int, int> MONTH_DAY = {
  1: 31,
  2: 28,  // 闰年动态调整为29
  3: 31,
  4: 30,
  5: 31,
  6: 30,
  7: 31,
  8: 31,
  9: 30,
  10: 31,
  11: 30,
  12: 31,
};

// 预编译正则表达式，提升解析性能
final RegExp _dateFormatRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _shortDateRegex = RegExp(r'^\d{6}$');

// 星期名称常量，用于快速查表
const List<String> _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _weekdaysZh = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const List<String> _weekdaysZhShort = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 日期时间工具类
class DateUtil {
  /// 解析日期字符串为DateTime，支持UTC或本地时间转换，失败返回null
  static DateTime? getDateTime(String dateStr, {bool? isUtc}) {
    DateTime? dateTime = DateTime.tryParse(dateStr);
    if (isUtc != null) {
      if (isUtc) {
        dateTime = dateTime?.toUtc();
      } else {
        dateTime = dateTime?.toLocal();
      }
    }
    return dateTime;
  }

  /// 将毫秒时间戳转为DateTime，默认本地时间
  static DateTime getDateTimeByMs(int ms, {bool isUtc = false}) {
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: isUtc);
  }

  /// 解析日期字符串为毫秒时间戳，失败返回null
  static int? getDateMsByTimeStr(String dateStr, {bool? isUtc}) {
    DateTime? dateTime = getDateTime(dateStr, isUtc: isUtc);
    return dateTime?.millisecondsSinceEpoch;
  }

  /// 获取当前毫秒时间戳
  static int getNowDateMs() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// 获取当前格式化日期字符串
  static String getNowDateStr() {
    return formatDate(DateTime.now());
  }

  /// 格式化毫秒时间戳为字符串
  static String formatDateMs(int ms, {bool isUtc = false, String? format}) {
    return formatDate(getDateTimeByMs(ms, isUtc: isUtc), format: format);
  }

  /// 格式化日期字符串
  static String formatDateStr(String dateStr, {bool? isUtc, String? format}) {
    return formatDate(getDateTime(dateStr, isUtc: isUtc), format: format);
  }

  /// 格式化DateTime为字符串
  static String formatDate(DateTime? dateTime, {String? format}) {
    if (dateTime == null) return '';
    format = format ?? DateFormats.full;
    
    final buffer = StringBuffer();
    int i = 0;
    
    while (i < format.length) {
      if (i + 4 <= format.length && format.substring(i, i + 4) == 'yyyy') {
        buffer.write(dateTime.year.toString());
        i += 4;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'yy') {
        final yearStr = dateTime.year.toString();
        buffer.write(yearStr.substring(yearStr.length - 2));
        i += 2;
      } else if (i + 3 <= format.length && format.substring(i, i + 3) == 'SSS') {
        buffer.write(dateTime.millisecond.toString().padLeft(3, '0'));
        i += 3;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'MM') {
        buffer.write(dateTime.month.toString().padLeft(2, '0'));
        i += 2;
      } else if (i + 1 <= format.length && format[i] == 'M' && (i + 1 >= format.length || format[i + 1] != 'M')) {
        buffer.write(dateTime.month.toString());
        i += 1;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'dd') {
        buffer.write(dateTime.day.toString().padLeft(2, '0'));
        i += 2;
      } else if (i + 1 <= format.length && format[i] == 'd' && (i + 1 >= format.length || format[i + 1] != 'd')) {
        buffer.write(dateTime.day.toString());
        i += 1;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'HH') {
        buffer.write(dateTime.hour.toString().padLeft(2, '0'));
        i += 2;
      } else if (i + 1 <= format.length && format[i] == 'H' && (i + 1 >= format.length || format[i + 1] != 'H')) {
        buffer.write(dateTime.hour.toString());
        i += 1;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'mm') {
        buffer.write(dateTime.minute.toString().padLeft(2, '0'));
        i += 2;
      } else if (i + 1 <= format.length && format[i] == 'm' && (i + 1 >= format.length || format[i + 1] != 'm')) {
        buffer.write(dateTime.minute.toString());
        i += 1;
      } else if (i + 2 <= format.length && format.substring(i, i + 2) == 'ss') {
        buffer.write(dateTime.second.toString().padLeft(2, '0'));
        i += 2;
      } else if (i + 1 <= format.length && format[i] == 's' && (i + 1 >= format.length || format[i + 1] != 's')) {
        buffer.write(dateTime.second.toString());
        i += 1;
      } else if (i + 1 <= format.length && format[i] == 'S' && (i + 1 >= format.length || format[i + 1] != 'S')) {
        buffer.write(dateTime.millisecond.toString());
        i += 1;
      } else {
        buffer.write(format[i]);
        i += 1;
      }
    }
    
    return buffer.toString();
  }

  /// 格式化数值到指定格式，支持单/双字符占位
  static String _comFormat(int value, String format, String single, String full) {
    if (!format.contains(single)) return format;
    if (format.contains(full)) {
      return format.replaceAll(full, value < 10 ? '0$value' : '$value');
    }
    return format.replaceAll(single, '$value');
  }

  /// 获取星期名称，支持中英文及短格式
  static String getWeekday(DateTime? dateTime,
      {String languageCode = 'en', bool short = false}) {
    if (dateTime == null) return "";
    
    final weekdayIndex = dateTime.weekday - 1; // 转换为0-6索引
    
    if (languageCode == 'zh') {
      return short ? _weekdaysZhShort[weekdayIndex] : _weekdaysZh[weekdayIndex];
    } else {
      final weekday = _weekdaysEn[weekdayIndex];
      return short ? weekday.substring(0, 3) : weekday;
    }
  }

  /// 通过毫秒获取星期名称，支持中英文及短格式
  static String getWeekdayByMs(int milliseconds,
      {bool isUtc = false, String languageCode = 'en', bool short = false}) {
    DateTime dateTime = getDateTimeByMs(milliseconds, isUtc: isUtc);
    return getWeekday(dateTime, languageCode: languageCode, short: short);
  }

  /// 获取一年中的第几天
  static int getDayOfYear(DateTime dateTime) {
    int year = dateTime.year;
    int month = dateTime.month;
    int days = dateTime.day;
    for (int i = 1; i < month; i++) {
      days = days + (i == 2 && isLeapYearByYear(year) ? 29 : MONTH_DAY[i]!);
    }
    return days;
  }

  /// 通过毫秒获取一年中的第几天
  static int getDayOfYearByMs(int ms, {bool isUtc = false}) {
    return getDayOfYear(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: isUtc));
  }

  /// 判断是否为当天
  static bool isToday(int? milliseconds, {bool isUtc = false, int? locMs}) {
    if (milliseconds == null || milliseconds == 0) return false;
    DateTime old = getDateTimeByMs(milliseconds, isUtc: isUtc);
    DateTime now;
    if (locMs != null) {
      now = getDateTimeByMs(locMs, isUtc: isUtc);
    } else {
      now = isUtc ? DateTime.now().toUtc() : DateTime.now().toLocal();
    }
    return old.year == now.year && old.month == now.month && old.day == now.day;
  }

  /// 判断是否为昨天
  static bool isYesterday(DateTime dateTime, DateTime locDateTime) {
    if (yearIsEqual(dateTime, locDateTime)) {
      int spDay = getDayOfYear(locDateTime) - getDayOfYear(dateTime);
      return spDay == 1;
    } else {
      return ((locDateTime.year - dateTime.year == 1) &&
          dateTime.month == 12 &&
          locDateTime.month == 1 &&
          dateTime.day == 31 &&
          locDateTime.day == 1);
    }
  }

  /// 通过毫秒判断是否为昨天
  static bool isYesterdayByMs(int ms, int locMs) {
    return isYesterday(getDateTimeByMs(ms), getDateTimeByMs(locMs));
  }

  /// 判断是否为本周
  static bool isWeek(int? ms, {bool isUtc = false, int? locMs}) {
    if (ms == null || ms <= 0) {
      return false;
    }
    DateTime _old = getDateTimeByMs(ms, isUtc: isUtc);
    DateTime _now;
    if (locMs != null) {
      _now = getDateTimeByMs(locMs, isUtc: isUtc);
    } else {
      _now = isUtc ? DateTime.now().toUtc() : DateTime.now().toLocal();
    }

    DateTime old =
        _now.millisecondsSinceEpoch > _old.millisecondsSinceEpoch ? _old : _now;
    DateTime now =
        _now.millisecondsSinceEpoch > _old.millisecondsSinceEpoch ? _now : _old;
    return (now.weekday >= old.weekday) &&
        (now.millisecondsSinceEpoch - old.millisecondsSinceEpoch <=
            7 * 24 * 60 * 60 * 1000);
  }

  /// 判断是否同年
  static bool yearIsEqual(DateTime dateTime, DateTime locDateTime) {
    return dateTime.year == locDateTime.year;
  }

  /// 通过毫秒判断是否同年
  static bool yearIsEqualByMs(int ms, int locMs) {
    return yearIsEqual(getDateTimeByMs(ms), getDateTimeByMs(locMs));
  }

  /// 判断是否为闰年
  static bool isLeapYear(DateTime dateTime) {
    return isLeapYearByYear(dateTime.year);
  }

  /// 通过年份判断是否为闰年
  static bool isLeapYearByYear(int year) {
    return year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
  }

  /// 解析自定义格式日期字符串
  static DateTime parseCustomDateTimeString(String dateTimeString) {
    try {
      // 匹配 yyyy-MM-dd 格式
      if (_dateFormatRegex.hasMatch(dateTimeString)) {
        return DateTime.parse(dateTimeString);
      }
      // 匹配 yyMMdd 格式
      if (_shortDateRegex.hasMatch(dateTimeString)) {
        final year = int.parse('20${dateTimeString.substring(0, 2)}');
        final month = int.parse(dateTimeString.substring(2, 4));
        final day = int.parse(dateTimeString.substring(4, 6));
        return DateTime(year, month, day);
      }
      // 匹配 yyyyMMddHHmmss +HHMM 格式
      final parts = dateTimeString.split(' ');
      final dateTimePart = parts[0];
      final timeZonePart = parts[1];


      final year = int.parse(dateTimePart.substring(0, 4));
      final month = int.parse(dateTimePart.substring(4, 6));
      final day = int.parse(dateTimePart.substring(6, 8));
      final hour = int.parse(dateTimePart.substring(8, 10));
      final minute = int.parse(dateTimePart.substring(10, 12));
      final second = int.parse(dateTimePart.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      throw FormatException('日期解析失败: $e');
    }
  }
}
