import 'package:iapp_player/src/core/iapp_player_utils.dart';

class IAppPlayerSubtitle {
  static const String timerSeparator = ' --> ';
  final int? index;
  final Duration? start;
  final Duration? end;
  final List<String>? texts;

  IAppPlayerSubtitle._({
    this.index,
    this.start,
    this.end,
    this.texts,
  });

  factory IAppPlayerSubtitle(String value, bool isWebVTT) {
    try {
      final scanner = value.split('\n');
      if (scanner.length == 2) {
        return _handle2LinesSubtitles(scanner);
      }
      if (scanner.length > 2) {
        return _handle3LinesAndMoreSubtitles(scanner, isWebVTT);
      }
      return IAppPlayerSubtitle._();
    } catch (exception) {
      IAppPlayerUtils.log("Failed to parse subtitle line: $value");
      return IAppPlayerSubtitle._();
    }
  }

  static IAppPlayerSubtitle _handle2LinesSubtitles(List<String> scanner) {
    try {
      final timeSplit = scanner[0].split(timerSeparator);
      final start = _stringToDuration(timeSplit[0]);
      final end = _stringToDuration(timeSplit[1]);
      final texts = scanner.sublist(1, scanner.length);

      return IAppPlayerSubtitle._(
          index: -1, start: start, end: end, texts: texts);
    } catch (exception) {
      IAppPlayerUtils.log("Failed to parse subtitle line: $scanner");
      return IAppPlayerSubtitle._();
    }
  }

  static IAppPlayerSubtitle _handle3LinesAndMoreSubtitles(
      List<String> scanner, bool isWebVTT) {
    try {
      int? index = -1;
      List<String> timeSplit = [];
      int firstLineOfText = 0;
      if (scanner[0].contains(timerSeparator)) {
        timeSplit = scanner[0].split(timerSeparator);
        firstLineOfText = 1;
      } else {
        index = int.tryParse(scanner[0]);
        timeSplit = scanner[1].split(timerSeparator);
        firstLineOfText = 2;
      }

      final start = _stringToDuration(timeSplit[0]);
      final end = _stringToDuration(timeSplit[1]);
      final texts = scanner.sublist(firstLineOfText, scanner.length);
      return IAppPlayerSubtitle._(
          index: index, start: start, end: end, texts: texts);
    } catch (exception) {
      IAppPlayerUtils.log("Failed to parse subtitle line: $scanner");
      return IAppPlayerSubtitle._();
    }
  }

  static Duration _stringToDuration(String value) {
    try {
      // 保持原始逻辑，但优化实现
      final trimmedValue = value.trim();
      final spaceIndex = trimmedValue.indexOf(' ');
      final componentValue = spaceIndex > 0 
          ? trimmedValue.substring(0, spaceIndex) 
          : trimmedValue;

      final component = componentValue.split(':');
      // Interpret a missing hour component to mean 00 hours
      if (component.length == 2) {
        component.insert(0, "00");
      } else if (component.length != 3) {
        return const Duration();
      }

      // 修复：保持原始的分隔符查找逻辑
      final secondsComponent = component[2];
      final secsAndMillisSplitChar = secondsComponent.contains(',') ? ',' : '.';
      final secsAndMillsSplit = secondsComponent.split(secsAndMillisSplitChar);
      
      if (secsAndMillsSplit.length != 2) {
        return const Duration();
      }

      // 安全解析，避免强制解包
      final hours = int.tryParse(component[0]);
      final minutes = int.tryParse(component[1]);
      final seconds = int.tryParse(secsAndMillsSplit[0]);
      final milliseconds = int.tryParse(secsAndMillsSplit[1]);

      if (hours == null || minutes == null || seconds == null || milliseconds == null) {
        return const Duration();
      }

      return Duration(
          hours: hours,
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds);
    } catch (exception) {
      IAppPlayerUtils.log("Failed to process value: $value");
      return const Duration();
    }
  }

  @override
  String toString() {
    return 'IAppPlayerSubtitle{index: $index, start: $start, end: $end, texts: $texts}';
  }
}
