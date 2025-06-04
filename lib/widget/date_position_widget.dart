import 'dart:async';
import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/date_util.dart';

class DatePositionWidget extends StatefulWidget {
  const DatePositionWidget({super.key});

  @override
  State<DatePositionWidget> createState() => _DatePositionWidgetState();
}

class _DatePositionWidgetState extends State<DatePositionWidget> {
  late Timer _timer; // 定时器，用于定期更新时间
  String _formattedDate = ''; // 缓存格式化后的日期
  String _formattedWeekday = ''; // 缓存格式化后的星期
  String _formattedTime = ''; // 缓存格式化后的时间
  bool _isLandscape = false; // 缓存屏幕方向
  String _locale = ''; // 缓存语言环境
  String _lastDisplayedTime = ''; // 缓存上次显示的时间，用于智能更新

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
  
  // 预创建的 TextStyle 对象，避免在 build 中重复创建
  late final TextStyle _dateLandscapeStyle;
  late final TextStyle _datePortraitStyle;
  late final TextStyle _timeLandscapeStyle;
  late final TextStyle _timePortraitStyle;

  @override
  void initState() {
    super.initState();
    
    // 初始化预创建的 TextStyle 对象
    _dateLandscapeStyle = _sharedTextStyle.copyWith(fontSize: _dateFontSizeLandscape);
    _datePortraitStyle = _sharedTextStyle.copyWith(fontSize: _dateFontSizePortrait);
    _timeLandscapeStyle = _sharedTextStyle.copyWith(fontSize: _timeFontSizeLandscape);
    _timePortraitStyle = _sharedTextStyle.copyWith(fontSize: _timeFontSizePortrait);
    
    // 初始化时间格式化结果和屏幕方向
    _updateTimeAndFormats();
    _lastDisplayedTime = _formattedTime;
    
    // 初始化定时器，按指定秒数更新时间状态
    _timer = Timer.periodic(Duration(seconds: _updateIntervalSeconds), (timer) {
      _updateTimeAndFormats();
      // 智能更新：只有当显示的时间发生变化时才触发 UI 重绘
      if (_lastDisplayedTime != _formattedTime) {
        _lastDisplayedTime = _formattedTime;
        setState(() {
          // 状态已在 _updateTimeAndFormats 中更新
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在依赖变化时更新屏幕方向和语言环境，例如屏幕旋转或语言切换
    final newIsLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final newLocale = Localizations.localeOf(context).toLanguageTag();
    
    // 智能更新：只有在屏幕方向或语言环境真正改变时才更新
    if (_isLandscape != newIsLandscape || _locale != newLocale) {
      _isLandscape = newIsLandscape;
      _locale = newLocale;
      _updateTimeAndFormats(); // 确保时间格式与新语言环境一致
      // 修正：需要立即更新UI以反映屏幕方向或语言的变化
      setState(() {});
    }
  }

  @override
  void dispose() {
    // 清理定时器，防止资源泄漏
    _timer.cancel();
    super.dispose();
  }

  // 更新时间并缓存格式化结果，避免在 build 中重复计算
  void _updateTimeAndFormats() {
    final currentTime = DateTime.now(); // 使用局部变量，不需要成员变量
    
    // 智能更新：只有当日期变化时才重新格式化日期和星期
    final currentDate = DateUtil.formatDate(
      currentTime,
      format: _locale.startsWith('zh') ? DateFormats.zh_y_mo_d : DateFormats.y_mo_d,
    );
    if (_formattedDate != currentDate) {
      _formattedDate = currentDate;
      _formattedWeekday = DateUtil.getWeekday(
        currentTime,
        languageCode: _locale.startsWith('zh') ? 'zh' : 'en',
      );
    }
    
    _formattedTime = DateUtil.formatDate(currentTime, format: 'HH:mm');
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
              style: _isLandscape ? _dateLandscapeStyle : _datePortraitStyle, // 使用预创建的样式
            ),
            // 显示时间，位于日期和星期的下方
            Positioned(
              top: _isLandscape ? _timeTopOffsetLandscape : _timeTopOffsetPortrait, // 根据屏幕方向调整垂直位置
              right: 0,
              child: Text(
                _formattedTime,
                style: _isLandscape ? _timeLandscapeStyle : _timePortraitStyle, // 使用预创建的样式
              ),
            ),
          ],
        ),
      ),
    );
  }
}
