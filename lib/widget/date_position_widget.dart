import 'dart:async';
import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/date_util.dart';

class DatePositionWidget extends StatefulWidget {
  const DatePositionWidget({super.key});

  @override
  State<DatePositionWidget> createState() => _DatePositionWidgetState();
}

class _DatePositionWidgetState extends State<DatePositionWidget> {
  DateTime _currentTime = DateTime.now(); // 当前时间状态
  late Timer _timer; // 定时器，用于定期更新时间
  String _formattedDate = ''; // 缓存格式化后的日期
  String _formattedWeekday = ''; // 缓存格式化后的星期
  String _formattedTime = ''; // 缓存格式化后的时间
  bool _isLandscape = false; // 缓存屏幕方向
  String _locale = ''; // 缓存语言环境

  // 定义文字阴影效果，用于提升文本的视觉层次感
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: 3.0, // 模糊半径
      color: Colors.black, // 阴影颜色
      offset: Offset(0, 1), // 阴影偏移
    ),
  ];

  // 提取公共的 TextStyle，提升代码复用性
  static const TextStyle _sharedTextStyle = TextStyle(
    color: Colors.white, // 白色字体
    fontWeight: FontWeight.bold, // 粗体字体
    shadows: _textShadows, // 应用阴影效果
  );

  // 定义常量，方便后续调整
  static const int _updateIntervalSeconds = 30; // 时间更新间隔秒
  static const double _topPaddingLandscape = 12.0; // 横屏顶部间距
  static const double _topPaddingPortrait = 8.0; // 竖屏顶部间距
  static const double _rightPaddingLandscape = 16.0; // 横屏右侧间距
  static const double _rightPaddingPortrait = 6.0; // 竖屏右侧间距
  static const double _dateFontSizeLandscape = 16.0; // 横屏日期字体大小
  static const double _dateFontSizePortrait = 8.0; // 竖屏日期字体大小
  static const double _timeFontSizeLandscape = 38.0; // 横屏时间字体大小
  static const double _timeFontSizePortrait = 28.0; // 竖屏时间字体大小
  static const double _timeTopOffsetLandscape = 18.0; // 横屏时间顶部偏移
  static const double _timeTopOffsetPortrait = 12.0; // 竖屏时间顶部偏移

  @override
  void initState() {
    super.initState();
    // 初始化时间格式化结果和屏幕方向
    _updateTimeAndFormats();
    // 初始化定时器，按指定秒数更新时间状态
    _timer = Timer.periodic(Duration(seconds: _updateIntervalSeconds), (timer) {
      setState(() {
        _updateTimeAndFormats(); // 更新时间并触发 UI 重绘
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在依赖变化时更新屏幕方向和语言环境，例如屏幕旋转或语言切换
    _isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    _locale = Localizations.localeOf(context).toLanguageTag();
    _updateTimeAndFormats(); // 确保时间格式与新语言环境一致
  }

  @override
  void dispose() {
    // 清理定时器，防止资源泄漏
    _timer.cancel();
    super.dispose();
  }

  // 更新时间并缓存格式化结果，避免在 build 中重复计算
  void _updateTimeAndFormats() {
    _currentTime = DateTime.now();
    _formattedDate = DateUtil.formatDate(
      _currentTime,
      format: _locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d,
    );
    _formattedWeekday = DateUtil.getWeekday(
      _currentTime,
      languageCode: _locale.startsWith('zh') ? 'zh' : 'en',
    );
    _formattedTime = DateUtil.formatDate(_currentTime, format: 'HH:mm');
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // 根据屏幕方向动态调整组件的垂直位置
      top: _isLandscape ? _topPaddingLandscape : _topPaddingPortrait,
      // 根据屏幕方向动态调整组件的水平位置
      right: _isLandscape ? _rightPaddingLandscape : _rightPaddingPortrait,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none, // 允许超出父组件范围的绘制
          children: [
            // 显示日期和星期信息
            Text(
              "$_formattedDate $_formattedWeekday",
              style: _sharedTextStyle.copyWith(
                fontSize: _isLandscape ? _dateFontSizeLandscape : _dateFontSizePortrait, // 根据屏幕方向调整字体大小
              ),
            ),
            // 显示时间，位于日期和星期的下方
            Positioned(
              top: _isLandscape ? _timeTopOffsetLandscape : _timeTopOffsetPortrait, // 根据屏幕方向调整垂直位置
              right: 0,
              child: Text(
                _formattedTime,
                style: _sharedTextStyle.copyWith(
                  fontSize: _isLandscape ? _timeFontSizeLandscape : _timeFontSizePortrait, // 根据屏幕方向调整字体大小
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
