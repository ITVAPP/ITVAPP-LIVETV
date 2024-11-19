import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import '../util/font_util.dart';
import '../util/env_util.dart';
import '../util/log_util.dart';
import '../config.dart';

class ThemeProvider extends ChangeNotifier {
  // 使用单例模式
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;

  late String _fontFamily; // 默认字体
  late double _textScaleFactor; // 默认文本缩放比例
  late bool _isLogOn; // 默认日志开关状态
  late bool _isBingBg; // 默认Bing背景设置
  late String _fontUrl; // 默认字体 URL 为空
  late bool _isTV; // 默认不是 TV 设备

  // 标记是否需要通知 UI 更新，避免不必要的重绘
  bool _shouldNotify = false;

  // 标记初始化是否完成
  bool _isInitialized = false;

  // 私有构造函数
  ThemeProvider._internal() {
    initialize();
  }

  bool get isInitialized => _isInitialized; // 获取初始化状态
  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn; // 获取日志开关状态

  // 通知 UI 更新，仅在必要时调用
  void _notifyIfNeeded() {
    if (_shouldNotify) {
      _shouldNotify = false; // 重置通知标记
      notifyListeners(); // 通知 UI 更新
    }
  }

  // 初始化方法，捕获并记录初始化中的异常
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await LogUtil.safeExecute(() async {
        final Map<String, dynamic> settings = await _loadAllSettings();
        _applySettings(settings);
        
        if (_fontFamily != Config.defaultFontFamily) {
          await FontUtil().loadFont(_fontUrl, _fontFamily);
        }

        _isInitialized = true;
        notifyListeners();
      }, '初始化 ThemeProvider 时出错');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化 ThemeProvider 时出错', e, stackTrace);
    }
  }

  // 批量加载所有设置
  Future<Map<String, dynamic>> _loadAllSettings() async {
    return {
      'fontFamily': SpUtil.getString('appFontFamily', defValue: Config.defaultFontFamily),
      'fontUrl': SpUtil.getString('appFontUrl', defValue: ''),
      'textScaleFactor': SpUtil.getDouble('fontScale', defValue: Config.defaultTextScaleFactor),
      'isBingBg': SpUtil.getBool('bingBg', defValue: Config.defaultBingBg),
      'isTV': SpUtil.getBool('isTV', defValue: false),
      'isLogOn': SpUtil.getBool('LogOn', defValue: Config.defaultLogOn),
    };
  }

  // 批量应用所有设置
  void _applySettings(Map<String, dynamic> settings) {
    _fontFamily = settings['fontFamily'] ?? Config.defaultFontFamily;
    _fontUrl = settings['fontUrl'] ?? '';
    _textScaleFactor = settings['textScaleFactor'] ?? Config.defaultTextScaleFactor;
    _isBingBg = settings['isBingBg'] ?? Config.defaultBingBg;
    _isTV = settings['isTV'] ?? false;
    _isLogOn = settings['isLogOn'] ?? Config.defaultLogOn;
    
    LogUtil.setDebugMode(_isLogOn);
    LogUtil.d(
      '配置信息:\n'
      '字体: $_fontFamily\n'
      '字体 URL: $_fontUrl\n'
      '文本缩放比例: $_textScaleFactor\n'
      'Bing 背景启用: ${_isBingBg ? "启用" : "未启用"}\n'
      '是否为 TV: ${_isTV ? "是 TV 设备" : "不是 TV 设备"}\n'
      '日志开关状态: ${_isLogOn ? "已开启" : "已关闭"}'
    );
  }

  // 设置日志开关状态，捕获并记录异步操作中的异常
  Future<void> setLogOn(bool isOpen) async {
    try {
      if (_isLogOn != isOpen) {
        _isLogOn = isOpen;
        await SpUtil.putBool('LogOn', isOpen);
        LogUtil.setDebugMode(_isLogOn);
        _shouldNotify = true;
        _notifyIfNeeded();
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
        await Future.wait([
          SpUtil.putString('appFontFamily', fontFamilyName),
          SpUtil.putString('appFontUrl', fontFullUrl),
        ]);
        _shouldNotify = true;
        _notifyIfNeeded();
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
        await SpUtil.putDouble('fontScale', textScaleFactor);
        _shouldNotify = true;
        _notifyIfNeeded();
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
        await SpUtil.putBool('bingBg', isOpen);
        _shouldNotify = true;
        _notifyIfNeeded();
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
        await setIsTV(deviceIsTV);
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
        await SpUtil.putBool('isTV', _isTV);
        _shouldNotify = true;
        _notifyIfNeeded();
      }
    } catch (error, stackTrace) {
      LogUtil.logError('手动设置 TV 状态时出错', error, stackTrace);
    }
  }
}
