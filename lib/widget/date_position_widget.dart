import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/date_util.dart';

// 显示动态日期和时间的组件
class DatePositionWidget extends StatefulWidget {
  const DatePositionWidget({super.key});

  @override
  State<DatePositionWidget> createState() => _DatePositionWidgetState();
}

// 管理日期和时间显示状态
class _DatePositionWidgetState extends State<DatePositionWidget> {
  late Timer _timer; // 定时更新时间
  String _formattedDate = ''; // 缓存日期格式
  String _formattedWeekday = ''; // 缓存星期格式
  String _formattedTime = ''; // 缓存时间格式
  bool _isLandscape = false; // 缓存屏幕方向
  String _locale = ''; // 缓存语言环境
  String _lastDisplayedTime = ''; // 缓存上次显示时间，优化更新

  // 定义文字阴影效果
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: 3.0, // 阴影模糊半径
      color: Colors.black, // 阴影颜色
      offset: Offset(0, 1), // 阴影偏移
    ),
  ];

  // 定义公共文本样式
  static const TextStyle _sharedTextStyle = TextStyle(
    color: Colors.white, // 白色字体
    fontWeight: FontWeight.bold, // 粗体
    shadows: _textShadows, // 应用阴影
  );

  // 定义布局常量
  static const int _updateIntervalSeconds = 30; // 时间更新间隔（秒）
  static const double _topPaddingLandscape = 12.0; // 横屏顶部间距
  static const double _topPaddingPortrait = 8.0; // 竖屏顶部间距
  static const double _rightPaddingLandscape = 16.0; // 横屏右侧间距
  static const double _rightPaddingPortrait = 6.0; // 竖屏右侧间距
  
  // 字体大小
  // 缓存文本样式 - 一次性创建
  late TextStyle _dateLandscapeStyle;
  late TextStyle _datePortraitStyle;
  late TextStyle _timeLandscapeStyle;
  late TextStyle _timePortraitStyle;

  @override
  void initState() {
    super.initState();
    
    // 在 initState 中读取 isTV 并初始化样式
    _initializeTextStyles(context.read<ThemeProvider>().isTV);
    
    // 初始化并缓存时间格式与屏幕方向
    _updateTimeAndFormats();
    _lastDisplayedTime = _formattedTime;
    
    // 启动定时器，定期更新时间
    _timer = Timer.periodic(Duration(seconds: _updateIntervalSeconds), (timer) {
      _updateTimeAndFormats();
      // 智能更新，仅时间变化时重绘
      if (_lastDisplayedTime != _formattedTime) {
        _lastDisplayedTime = _formattedTime;
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 更新屏幕方向和语言环境
    final newIsLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final newLocale = Localizations.localeOf(context).toLanguageTag();
    
    // 智能更新，仅方向或语言变化时执行
    if (_isLandscape != newIsLandscape || _locale != newLocale) {
      _isLandscape = newIsLandscape;
      _locale = newLocale;
      _updateTimeAndFormats();
      setState(() {}); // 立即更新 UI
    }
  }

  @override
  void dispose() {
    _timer.cancel(); // 安全释放定时器
    super.dispose();
  }

  // 更新并缓存时间格式
  void _updateTimeAndFormats() {
    final currentTime = DateTime.now(); // 获取当前时间
    
    // 智能更新，仅日期变化时格式化
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

  // 初始化文本样式 - 一次性创建所有样式
  void _initializeTextStyles(bool isTV) {
    _dateLandscapeStyle = _sharedTextStyle.copyWith(fontSize: isTV ? 20.0 : 16.0); // TV模式增大25%
    _datePortraitStyle = _sharedTextStyle.copyWith(fontSize: isTV ? 10.0 : 8.0); // TV模式增大25%
    _timeLandscapeStyle = _sharedTextStyle.copyWith(fontSize: isTV ? 48.0 : 38.0); // TV模式增大约26%
    _timePortraitStyle = _sharedTextStyle.copyWith(fontSize: isTV ? 35.0 : 28.0); // TV模式增大25%
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // 适配屏幕方向的顶部间距
      top: _isLandscape ? _topPaddingLandscape : _topPaddingPortrait,
      // 适配屏幕方向的右侧间距
      right: _isLandscape ? _rightPaddingLandscape : _rightPaddingPortrait,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none, // 允许溢出绘制
          children: [
            // 显示日期和星期
            Text(
              "$_formattedDate $_formattedWeekday",
              style: _isLandscape ? _dateLandscapeStyle : _datePortraitStyle,
            ),
            // 显示时间，位于下方
            Positioned(
              top: _isLandscape ? _timeTopOffsetLandscape : _timeTopOffsetPortrait, // 适配时间偏移
              right: 0,
              child: Text(
                _formattedTime,
                style: _isLandscape ? _timeLandscapeStyle : _timePortraitStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
