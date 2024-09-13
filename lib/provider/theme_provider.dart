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
  bool _isLogOn = true; // 添加日志开关变量

  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn; // 获取日志开关状态

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
      _isLogOn = SpUtil.getBool('LogOn', defValue: true) ?? true; // 加载日志开关状态

      // 设置日志记录开关
      LogUtil.setDebugMode(_isLogOn);

      // 如果字体不是系统默认字体，则加载自定义字体
      if (_fontFamily != 'system') {
        FontUtil().loadFont(_fontUrl, _fontFamily);
      }
    }, '初始化 ThemeProvider 时出错');
  }

  // 设置日志开关状态，捕获并记录异步操作中的异常
  void setLogOn(bool isOpen) {
    try {
      SpUtil.putBool('LogOn', isOpen);
      _isLogOn = isOpen;
      LogUtil.setDebugMode(_isLogOn); // 在修改日志开关状态后再次设置日志开关
      notifyListeners(); // 通知 UI 更新
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关状态时出错', e, stackTrace);
    }
  }

  // 设置字体相关的方法，捕获并记录异步操作中的异常
  void setFontFamily(String fontFamilyName, [String fontFullUrl = '']) {
    try {
      SpUtil.putString('appFontFamily', fontFamilyName);
      SpUtil.putString('appFontUrl', fontFullUrl);
      _fontFamily = fontFamilyName;
      _fontUrl = fontFullUrl;
      notifyListeners();
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体时出错', e, stackTrace); // 捕获并记录异常
    }
  }

  // 设置文本缩放，捕获并记录异步操作中的异常
  void setTextScale(double textScaleFactor) {
    try {
      SpUtil.putDouble('fontScale', textScaleFactor);
      _textScaleFactor = textScaleFactor;
      notifyListeners();
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放时出错', e, stackTrace); // 捕获并记录异常
    }
  }

  // 设置每日 Bing 背景图片的开关状态，捕获并记录异步操作中的异常
  void setBingBg(bool isOpen) {
    try {
      SpUtil.putBool('bingBg', isOpen);
      _isBingBg = isOpen;
      notifyListeners();
    } catch (e, stackTrace) {
      LogUtil.logError('设置每日 Bing 背景时出错', e, stackTrace); // 捕获并记录异常
    }
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
