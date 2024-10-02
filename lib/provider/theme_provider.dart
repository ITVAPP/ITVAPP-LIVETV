import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import '../util/font_util.dart';
import '../util/env_util.dart';
import '../util/log_util.dart';
import '../config.dart';

class ThemeProvider extends ChangeNotifier {
  String _fontFamily = Config.defaultFontFamily; // 默认字体
  double _textScaleFactor = Config.defaultTextScaleFactor; // 默认文本缩放比例
  bool _isLogOn = Config.defaultLogOn; // 默认日志开关状态
  bool _isBingBg = Config.defaultBingBg; // 默认Bing背景设置
  String _fontUrl = ''; // 默认字体 URL 为空
  bool _isTV = false; // 默认不是 TV 设备

  // 标记是否需要通知 UI 更新，避免不必要的重绘
  bool _shouldNotify = false;

  // 标记初始化是否完成
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized; // 获取初始化状态

  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn; // 获取日志开关状态

  // 构造函数，在初始化时从缓存中加载数据
  ThemeProvider() {
    initialize(); // 使用 _initialize 进行同步初始化
  }

  // 初始化方法，捕获并记录初始化中的异常
  Future<void> initialize() async {
    try {
      LogUtil.safeExecute(() async {
        _fontFamily = SpUtil.getString('appFontFamily', defValue: Config.defaultFontFamily) ?? Config.defaultFontFamily;
        _fontUrl = SpUtil.getString('appFontUrl') ?? '';
        _textScaleFactor = SpUtil.getDouble('fontScale', defValue: Config.defaultTextScaleFactor) ?? Config.defaultTextScaleFactor;
        _isBingBg = SpUtil.getBool('bingBg', defValue: Config.defaultBingBg) ?? Config.defaultBingBg;
        _isTV = SpUtil.getBool('isTV', defValue: false) ?? false;
        _isLogOn = SpUtil.getBool('LogOn', defValue: Config.defaultLogOn) ?? Config.defaultLogOn;

        // 记录初始化的各个值到日志
        LogUtil.d(
          '字体: $_fontFamily\n'
          '字体 URL: $_fontUrl\n'
          '文本缩放比例: $_textScaleFactor\n'
          'Bing 背景启用: ${_isBingBg ? "启用" : "未启用"}\n'
          '是否为 TV: ${_isTV ? "是 TV 设备" : "不是 TV 设备"}\n'
          '日志开关状态: ${_isLogOn ? "已开启" : "已关闭"}'
        );

        // 设置日志记录开关
        LogUtil.setDebugMode(_isLogOn);

        // 如果字体不是系统默认字体，则加载自定义字体
        if (_fontFamily != Config.defaultFontFamily) {
          FontUtil().loadFont(_fontUrl, _fontFamily);
        }

        _isInitialized = true; // 标记初始化完成
        notifyListeners(); // 通知 UI 更新
      }, '初始化 ThemeProvider 时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化 ThemeProvider 时出错', e, stackTrace);
    }
  }

  // 通知 UI 更新，仅在必要时调用
  void _notifyIfNeeded() {
    if (_shouldNotify) {
      _shouldNotify = false; // 重置通知标记
      notifyListeners(); // 通知 UI 更新
    }
  }

  // 设置日志开关状态，捕获并记录异步操作中的异常
  Future<void> setLogOn(bool isOpen) async {
    try {
      if (_isLogOn != isOpen) {
        _isLogOn = isOpen;
        SpUtil.putBool('LogOn', isOpen); // 使用 SpUtil 存储日志开关状态
        LogUtil.setDebugMode(_isLogOn); // 在修改日志开关状态后再次设置日志开关
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关状态时出错', e, stackTrace);
    }
  }

  // 设置字体相关的方法，捕获并记录异步操作中的异常
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      if (_fontFamily != fontFamilyName || _fontUrl != fontFullUrl) {
        _fontFamily = fontFamilyName;
        _fontUrl = fontFullUrl;
        SpUtil.putString('appFontFamily', fontFamilyName); // 使用 SpUtil 存储字体
        SpUtil.putString('appFontUrl', fontFullUrl);
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体时出错', e, stackTrace);
    }
  }

  // 设置文本缩放比例，捕获并记录异步操作中的异常
  Future<void> setTextScale(double textScaleFactor) async {
    try {
      if (_textScaleFactor != textScaleFactor) {
        _textScaleFactor = textScaleFactor;
        SpUtil.putDouble('fontScale', textScaleFactor); // 使用 SpUtil 存储文本缩放比例
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放时出错', e, stackTrace);
    }
  }

  // 设置每日 Bing 背景图片的开关状态，捕获并记录异步操作中的异常
  Future<void> setBingBg(bool isOpen) async {
    try {
      if (_isBingBg != isOpen) {
        _isBingBg = isOpen;
        SpUtil.putBool('bingBg', isOpen); // 使用 SpUtil 存储 Bing 背景开关状态
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置每日 Bing 背景时出错', e, stackTrace);
    }
  }

  // 检测并设置设备是否为 TV，捕获并记录异步操作中的异常
  Future<void> checkAndSetIsTV() async {
    try {
      bool deviceIsTV = await EnvUtil.isTV();
      if (_isTV != deviceIsTV) {
        _isTV = deviceIsTV;
        SpUtil.putBool('isTV', _isTV); // 使用 SpUtil 存储是否为 TV 的状态
        notifyListeners(); // 通知 UI 更新
      }
      LogUtil.i('设备检测结果: 该设备${deviceIsTV ? "是" : "不是"}TV');
    } catch (error, stackTrace) {
      LogUtil.logError('检测并设置设备为 TV 时出错', error, stackTrace);
    }
  }

  // 手动设置是否为 TV，捕获并记录异步操作中的异常
  Future<void> setIsTV(bool isTV) async {
    try {
      if (_isTV != isTV) {
        _isTV = isTV;
        SpUtil.putBool('isTV', _isTV); // 使用 SpUtil 存储 TV 状态
        notifyListeners(); // 通知 UI 更新
      }
    } catch (error, stackTrace) {
      LogUtil.logError('手动设置 TV 状态时出错', error, stackTrace);
    }
  }
}
