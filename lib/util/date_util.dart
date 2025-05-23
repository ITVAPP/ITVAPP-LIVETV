/// 一些常用格式参照。可以自定义格式，例如：'yyyy/MM/dd HH:mm:ss'，'yyyy/M/d HH:mm:ss'。
/// 格式要求
/// year -> yyyy/yy   month -> MM/M    day -> dd/d
/// hour -> HH/H      minute -> mm/m   second -> ss/s
class DateFormats {
  static String full = 'yyyy-MM-dd HH:mm:ss';
  static String y_mo_d_h_m = 'yyyy-MM-dd HH:mm';
  static String y_mo_d = 'yyyy-MM-dd';
  static String y_mo = 'yyyy-MM';
  static String mo_d = 'MM-dd';
  static String mo_d_h_m = 'MM-dd HH:mm';
  static String h_m_s = 'HH:mm:ss';
  static String h_m = 'HH:mm';

  static String zh_full = 'yyyy年MM月dd日 HH:mm:ss';  // 修改：去掉了“时”、“分”、“秒”的中文文字
  static String zh_y_mo_d_h_m = 'yyyy年MM月dd日 HH:mm'; // 修改：去掉了“时”、“分”
  static String zh_y_mo_d = 'yyyy年MM月dd日';
  static String zh_y_mo = 'yyyy年MM月';
  static String zh_mo_d = 'MM月dd日';
  static String zh_mo_d_h_m = 'MM月dd日 HH:mm'; // 修改：去掉了“时”、“分”
  static String zh_h_m_s = 'HH:mm:ss';         // 修改：去掉了“时”、“分”、“秒”
  static String zh_h_m = 'HH:mm';              // 修改：去掉了“时”、“分”
}

/// month->days. 定义为 const Map，提升访问效率并防止运行时修改
const Map<int, int> MONTH_DAY = {
  1: 31,
  2: 28,  // 注意：闰年情况在计算中动态处理
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

/// Date Util.
class DateUtil {
  /// get DateTime By DateStr.
  /// [dateStr] 日期字符串
  /// [isUtc] 是否转换为 UTC 时间
  /// 返回解析后的 DateTime 对象，若解析失败则返回 null
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

  /// get DateTime By Milliseconds.
  /// [ms] 毫秒时间戳
  /// [isUtc] 是否为 UTC 时间
  /// 返回对应的 DateTime 对象
  static DateTime getDateTimeByMs(int ms, {bool isUtc = false}) {
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: isUtc);
  }

  /// get DateMilliseconds By DateStr.
  /// [dateStr] 日期字符串
  /// [isUtc] 是否转换为 UTC 时间
  /// 返回毫秒时间戳，若解析失败则返回 null
  static int? getDateMsByTimeStr(String dateStr, {bool? isUtc}) {
    DateTime? dateTime = getDateTime(dateStr, isUtc: isUtc);
    return dateTime?.millisecondsSinceEpoch;
  }

  /// get Now Date Milliseconds.
  /// 返回当前时间的毫秒时间戳
  static int getNowDateMs() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// get Now Date Str.(yyyy-MM-dd HH:mm:ss)
  /// 返回当前时间的格式化字符串，默认格式为 DateFormats.full
  static String getNowDateStr() {
    return formatDate(DateTime.now());
  }

  /// format date by milliseconds.
  /// [ms] 毫秒时间戳
  /// [isUtc] 是否为 UTC 时间
  /// [format] 自定义格式，默认为 DateFormats.full
  static String formatDateMs(int ms, {bool isUtc = false, String? format}) {
    return formatDate(getDateTimeByMs(ms, isUtc: isUtc), format: format);
  }

  /// format date by date str.
  /// [dateStr] 日期字符串
  /// [isUtc] 是否转换为 UTC 时间
  /// [format] 自定义格式，默认为 DateFormats.full
  static String formatDateStr(String dateStr, {bool? isUtc, String? format}) {
    return formatDate(getDateTime(dateStr, isUtc: isUtc), format: format);
  }

  /// format date by DateTime.
  /// [dateTime] 需要格式化的 DateTime 对象
  /// [format] 转换格式，默认使用 DateFormats.full，支持自定义格式：'yyyy/MM/dd HH:mm:ss'
  /// 返回格式化后的日期字符串，若 dateTime 为 null 则返回空字符串
  static String formatDate(DateTime? dateTime, {String? format}) {
    if (dateTime == null) return '';
    // 使用 StringBuffer 优化字符串拼接性能
    final buffer = StringBuffer();
    format = format ?? DateFormats.full;

    // 处理年份
    String year = dateTime.year.toString();
    if (format.contains('yyyy')) {
      buffer.write(format.replaceAll('yyyy', year));
    } else if (format.contains('yy')) {
      buffer.write(format.replaceAll('yy', year.substring(year.length - 2)));
    } else {
      buffer.write(format);
    }
    format = buffer.toString();
    buffer.clear();

    // 统一处理月份、日期、小时等字段
    format = _comFormat(dateTime.month, format, 'M', 'MM');
    format = _comFormat(dateTime.day, format, 'd', 'dd');
    format = _comFormat(dateTime.hour, format, 'H', 'HH');
    format = _comFormat(dateTime.minute, format, 'm', 'mm');
    format = _comFormat(dateTime.second, format, 's', 'ss');
    format = _comFormat(dateTime.millisecond, format, 'S', 'SSS');

    return format;
  }

  /// com format.
  /// [value] 需要格式化的数值（如月份、日期等）
  /// [format] 当前格式字符串
  /// [single] 单字符占位（如 'M'）
  /// [full] 双字符占位（如 'MM'）
  /// 返回格式化后的字符串，确保数值正确填充到格式中
  static String _comFormat(int value, String format, String single, String full) {
    if (!format.contains(single)) return format;
    if (format.contains(full)) {
      return format.replaceAll(full, value < 10 ? '0$value' : '$value');
    }
    return format.replaceAll(single, '$value');
  }

  /// get WeekDay.
  /// dateTime
  /// isUtc
  /// languageCode zh or en
  /// short
  static String getWeekday(DateTime? dateTime,
      {String languageCode = 'en', bool short = false}) {
    if (dateTime == null) return "";
    String weekday = "";
    switch (dateTime.weekday) {
      case 1:
        weekday = languageCode == 'zh' ? '星期一' : 'Monday';
        break;
      case 2:
        weekday = languageCode == 'zh' ? '星期二' : 'Tuesday';
        break;
      case 3:
        weekday = languageCode == 'zh' ? '星期三' : 'Wednesday';
        break;
      case 4:
        weekday = languageCode == 'zh' ? '星期四' : 'Thursday';
        break;
      case 5:
        weekday = languageCode == 'zh' ? '星期五' : 'Friday';
        break;
      case 6:
        weekday = languageCode == 'zh' ? '星期六' : 'Saturday';
        break;
      case 7:
        weekday = languageCode == 'zh' ? '星期日' : 'Sunday';
        break;
      default:
        break;
    }
    return languageCode == 'zh'
        ? (short ? weekday.replaceAll('星期', '周') : weekday)
        : weekday.substring(0, short ? 3 : weekday.length);
  }

  /// get WeekDay By Milliseconds.
  static String getWeekdayByMs(int milliseconds,
      {bool isUtc = false, String languageCode = 'en', bool short = false}) {
    DateTime dateTime = getDateTimeByMs(milliseconds, isUtc: isUtc);
    return getWeekday(dateTime, languageCode: languageCode, short: short);
  }

  /// get day of year.
  /// 在今年的第几天.
  static int getDayOfYear(DateTime dateTime) {
    int year = dateTime.year;
    int month = dateTime.month;
    int days = dateTime.day;
    for (int i = 1; i < month; i++) {
      days = days + (i == 2 && isLeapYearByYear(year) ? 29 : MONTH_DAY[i]!);
    }
    return days;
  }

  /// get day of year.
  /// 在今年的第几天.
  static int getDayOfYearByMs(int ms, {bool isUtc = false}) {
    return getDayOfYear(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: isUtc));
  }

  /// is today.
  /// 是否是当天.
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

  /// is yesterday by dateTime.
  /// 是否是昨天.
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

  /// is yesterday by millis.
  /// 是否是昨天.
  static bool isYesterdayByMs(int ms, int locMs) {
    return isYesterday(getDateTimeByMs(ms), getDateTimeByMs(locMs));
  }

  /// is Week.
  /// 是否是本周.
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

  /// year is equal.
  /// 是否同年.
  static bool yearIsEqual(DateTime dateTime, DateTime locDateTime) {
    return dateTime.year == locDateTime.year;
  }

  /// year is equal.
  /// 是否同年.
  static bool yearIsEqualByMs(int ms, int locMs) {
    return yearIsEqual(getDateTimeByMs(ms), getDateTimeByMs(locMs));
  }

  /// Return whether it is leap year.
  /// 是否是闰年
  static bool isLeapYear(DateTime dateTime) {
    return isLeapYearByYear(dateTime.year);
  }

  /// Return whether it is leap year.
  /// 是否是闰年
  static bool isLeapYearByYear(int year) {
    return year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
  }

  /// 解析自定义格式的日期时间字符串
  /// [dateTimeString] 输入格式示例：'20230315123045 +0800' 或 'yyyy-MM-dd' 或 'yyMMdd'
  /// 返回解析后的 DateTime 对象，若格式错误则抛出异常
  static DateTime parseCustomDateTimeString(String dateTimeString) {
    try {
      // 支持 yyyy-MM-dd 格式（例如 '2025-04-12'）
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateTimeString)) {
        return DateTime.parse(dateTimeString);
      }
      // 支持 yyMMdd 格式（例如 '250412'）
      if (RegExp(r'^\d{6}$').hasMatch(dateTimeString)) {
        final year = int.parse('20${dateTimeString.substring(0, 2)}');
        final month = int.parse(dateTimeString.substring(2, 4));
        final day = int.parse(dateTimeString.substring(4, 6));
        return DateTime(year, month, day);
      }
      // 原有格式：yyyyMMddHHmmss +HHMM（例如 '20230315123045 +0800'）
      final parts = dateTimeString.split(' ');
      if (parts.length != 2) {
        throw FormatException('日期时间字符串格式错误，应包含日期和时区部分');
      }
      final dateTimePart = parts[0];
      final timeZonePart = parts[1];

      if (dateTimePart.length != 14 || timeZonePart.length != 5) {
        throw FormatException('日期时间或时区部分长度不正确');
      }

      final year = int.parse(dateTimePart.substring(0, 4));
      final month = int.parse(dateTimePart.substring(4, 6));
      final day = int.parse(dateTimePart.substring(6, 8));
      final hour = int.parse(dateTimePart.substring(8, 10));
      final minute = int.parse(dateTimePart.substring(10, 12));
      final second = int.parse(dateTimePart.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      throw FormatException('解析日期时间字符串失败: $e');
    }
  }
}
