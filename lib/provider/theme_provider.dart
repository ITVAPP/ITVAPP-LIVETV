import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  SharedPreferences? _prefs; // 缓存 SharedPreferences 实例

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
  Future<void> _initialize() async {
    try {
      LogUtil.safeExecute(() async {
        _prefs = await SharedPreferences.getInstance(); // 获取 SharedPreferences 实例并缓存
        _fontFamily = _prefs?.getString('appFontFamily') ?? 'system';
        _fontUrl = _prefs?.getString('appFontUrl') ?? '';
        _textScaleFactor = _prefs?.getDouble('fontScale') ?? 1.0;
        _isBingBg = _prefs?.getBool('bingBg') ?? false;
        _isTV = _prefs?.getBool('isTV') ?? false;
        _isLogOn = _prefs?.getBool('LogOn') ?? true; // 加载日志开关状态

        // 设置日志记录开关
        LogUtil.setDebugMode(_isLogOn);

        // 如果字体不是系统默认字体，则加载自定义字体
        if (_fontFamily != 'system') {
          FontUtil().loadFont(_fontUrl, _fontFamily);
        }

        notifyListeners(); // 通知 UI 更新
      }, '初始化 ThemeProvider 时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化 ThemeProvider 时出错', e, stackTrace);
    }
  }

  // 设置日志开关状态，捕获并记录异步操作中的异常
  Future<void> setLogOn(bool isOpen) async {
    try {
      LogUtil.safeExecute(() async {
        await _prefs?.setBool('LogOn', isOpen); // 使用已缓存的 SharedPreferences 实例
        _isLogOn = isOpen;
        LogUtil.setDebugMode(_isLogOn); // 在修改日志开关状态后再次设置日志开关
        notifyListeners(); // 通知 UI 更新
      }, '设置日志开关状态时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关状态时出错', e, stackTrace);
    }
  }

  // 设置字体相关的方法，捕获并记录异步操作中的异常
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      LogUtil.safeExecute(() async {
        await _prefs?.setString('appFontFamily', fontFamilyName); // 使用缓存的 SharedPreferences 实例
        await _prefs?.setString('appFontUrl', fontFullUrl);
        _fontFamily = fontFamilyName;
        _fontUrl = fontFullUrl;
        notifyListeners(); // 通知 UI 更新
      }, '设置字体时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体时出错', e, stackTrace);
    }
  }

  // 设置文本缩放，捕获并记录异步操作中的异常
  Future<void> setTextScale(double textScaleFactor) async {
    try {
      LogUtil.safeExecute(() async {
        await _prefs?.setDouble('fontScale', textScaleFactor); // 使用缓存的 SharedPreferences 实例
        _textScaleFactor = textScaleFactor;
        notifyListeners(); // 通知 UI 更新
      }, '设置文本缩放时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放时出错', e, stackTrace);
    }
  }

  // 设置每日 Bing 背景图片的开关状态，捕获并记录异步操作中的异常
  Future<void> setBingBg(bool isOpen) async {
    try {
      LogUtil.safeExecute(() async {
        await _prefs?.setBool('bingBg', isOpen); // 使用缓存的 SharedPreferences 实例
        _isBingBg = isOpen;
        notifyListeners(); // 通知 UI 更新
      }, '设置每日 Bing 背景时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('设置每日 Bing 背景时出错', e, stackTrace);
    }
  }

  // 检测并设置设备是否为 TV，捕获并记录异步操作中的异常
  Future<void> checkAndSetIsTV() async {
    try {
      LogUtil.safeExecute(() async {
        bool deviceIsTV = await EnvUtil.isTV(); // 调用工具类检测是否为 TV
        _isTV = deviceIsTV;
        await _prefs?.setBool('isTV', _isTV); // 使用缓存的 SharedPreferences 实例
        notifyListeners(); // 通知监听器更新界面
      }, '检测并设置设备为 TV 时出错');
    } catch (error, stackTrace) {
      LogUtil.logError('检测并设置设备为 TV 时出错', error, stackTrace);
    }
  }

  // 手动设置是否为 TV，捕获并记录异步操作中的异常
  Future<void> setIsTV(bool isTV) async {
    try {
      LogUtil.safeExecute(() async {
        _isTV = isTV;
        await _prefs?.setBool('isTV', _isTV);  // 使用缓存的 SharedPreferences 实例
        notifyListeners(); // 通知监听器更新界面
      }, '手动设置 TV 状态时出错');
    } catch (error, stackTrace) {
      LogUtil.logError('手动设置 TV 状态时出错', error, stackTrace);
    }
  }
}
