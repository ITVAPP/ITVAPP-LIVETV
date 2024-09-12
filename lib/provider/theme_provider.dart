import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import '../util/font_util.dart';
import '../util/env_util.dart'; // 导入用于检测设备的工具类
import '../util/log_util.dart'; // 导入日志工具

class ThemeProvider extends ChangeNotifier {
  String _fontFamily = 'system';
  double _textScaleFactor = 1.0;
  String _fontUrl = '';
  bool _isBingBg = false;
  bool _isTV = false; // 添加 isTV 变量
  bool debugMode = LogUtil.debugMode; // 初始值从 LogUtil 中获取

  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV; // 添加获取 isTV 的方法

  // 构造函数，在初始化时从缓存中加载数据
  ThemeProvider() {
    _initialize();
  }

  // 初始化方法，捕获并记录初始化中的异常
  void _initialize() {
    LogUtil.safeExecute(() {
      _fontFamily = SpUtil.getString('appFontFamily', defValue: 'system') ?? 'system';
      _fontUrl = SpUtil.getString('appFontUrl', defValue: '') ?? '';
      _textScaleFactor = SpUtil.getDouble('fontScale', defValue: 1.0) ?? 1.0;
      _isBingBg = SpUtil.getBool('bingBg', defValue: false) ?? false;
      _isTV = SpUtil.getBool('isTV', defValue: false) ?? false;

      // 如果字体不是系统默认字体，则加载自定义字体
      if (_fontFamily != 'system') {
        FontUtil().loadFont(_fontUrl, _fontFamily);
      }
    }, '初始化 ThemeProvider 时出错');
  }

  // 设置字体相关的方法，捕获并记录异步操作中的异常
  void setFontFamily(String fontFamilyName, [String fontFullUrl = '']) {
    SpUtil.putString('appFontFamily', fontFamilyName);
    SpUtil.putString('appFontUrl', fontFullUrl);
    _fontFamily = fontFamilyName;
    _fontUrl = fontFullUrl;
    notifyListeners();
  }

  // 设置文本缩放，捕获并记录异步操作中的异常
  void setTextScale(double textScaleFactor) {
    SpUtil.putDouble('fontScale', textScaleFactor);
    _textScaleFactor = textScaleFactor;
    notifyListeners();
  }

  // 设置每日 Bing 背景图片的开关状态，捕获并记录异步操作中的异常
  void setBingBg(bool isOpen) {
    SpUtil.putBool('bingBg', isOpen);
    _isBingBg = isOpen;
    notifyListeners();
  }

  // 设置记录日志的开关状态
  void setDebugMode(bool debugMode) {
    SpUtil.putBool('debugMode', debugMode);
    this.debugMode = debugMode;
    notifyListeners();
  }

  // 检测并设置设备是否为 TV，捕获并记录异步操作中的异常
  Future<void> checkAndSetIsTV() async {
    try {
      bool deviceIsTV = await EnvUtil.isTV(); // 调用工具类检测是否为 TV
      _isTV = deviceIsTV;
      await SpUtil.putBool('isTV', _isTV); // 异步存储结果
      notifyListeners(); // 通知监听器更新界面
    } catch (error, stackTrace) {
      LogUtil.logError('检测并设置设备为 TV 时出错', error, stackTrace);
    }
  }

  // 手动设置是否为 TV，捕获并记录异步操作中的异常
  Future<void> setIsTV(bool isTV) async {
    try {
      _isTV = isTV;
      await SpUtil.putBool('isTV', _isTV);  // 异步存储状态
      notifyListeners(); // 通知监听器更新界面
    } catch (error, stackTrace) {
      LogUtil.logError('手动设置 TV 状态时出错', error, stackTrace);
    }
  }
}
