import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  SharedPreferences? _prefs; // 缓存 SharedPreferences 实例

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
    Future.microtask(() => _initialize()); // 使用 Future.microtask 确保异步任务在构造函数完成后执行
  }

  // 确保 SharedPreferences 已初始化
  Future<void> _ensurePrefsInitialized() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  // 初始化方法，捕获并记录初始化中的异常
  Future<void> _initialize() async {
    try {
      LogUtil.safeExecute(() async {
        await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化

        // 读取各项设置的值，读取不到则使用默认值
        _fontFamily = _prefs?.getString('appFontFamily') ?? Config.defaultFontFamily; // 使用默认字体
        _fontUrl = _prefs?.getString('appFontUrl') ?? ''; // 读取字体URL，默认空
        _textScaleFactor = _prefs?.getDouble('fontScale') ?? Config.defaultTextScaleFactor; // 使用默认文本缩放比例
        _isBingBg = _prefs?.getBool('bingBg') ?? Config.defaultBingBg; // 使用默认 Bing 背景设置
        _isTV = _prefs?.getBool('isTV') ?? false; // 读取是否 TV 设备设置，默认 false
        _isLogOn = _prefs?.getBool('LogOn') ?? Config.defaultLogOn; // 使用默认日志开关

        // 设置日志记录开关
        LogUtil.setDebugMode(_isLogOn);

        // 如果字体不是系统默认字体，则加载自定义字体
        if (_fontFamily != Config.defaultFontFamily) {
          FontUtil().loadFont(_fontUrl, _fontFamily);
        }

        _shouldNotify = true; // 标记数据已更新，需要通知 UI
        _isInitialized = true; // 标记初始化完成
        _notifyIfNeeded(); // 通知 UI 更新
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
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      if (_isLogOn != isOpen) {
        LogUtil.safeExecute(() async {
          await _prefs?.setBool('LogOn', isOpen); // 使用已缓存的 SharedPreferences 实例
          _isLogOn = isOpen;
          LogUtil.setDebugMode(_isLogOn); // 在修改日志开关状态后再次设置日志开关
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知 UI 更新
        }, '设置日志开关状态时出错');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关状态时出错', e, stackTrace);
    }
  }

  // 设置字体相关的方法，捕获并记录异步操作中的异常
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      if (_fontFamily != fontFamilyName || _fontUrl != fontFullUrl) {
        LogUtil.safeExecute(() async {
          await _prefs?.setString('appFontFamily', fontFamilyName); // 使用缓存的 SharedPreferences 实例
          await _prefs?.setString('appFontUrl', fontFullUrl);
          _fontFamily = fontFamilyName;
          _fontUrl = fontFullUrl;
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知 UI 更新
        }, '设置字体时出错');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体时出错', e, stackTrace);
    }
  }

  // 设置文本缩放，捕获并记录异步操作中的异常
  Future<void> setTextScale(double textScaleFactor) async {
    try {
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      if (_textScaleFactor != textScaleFactor) {
        LogUtil.safeExecute(() async {
          await _prefs?.setDouble('fontScale', textScaleFactor); // 使用缓存的 SharedPreferences 实例
          _textScaleFactor = textScaleFactor;
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知 UI 更新
        }, '设置文本缩放时出错');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放时出错', e, stackTrace);
    }
  }

  // 设置每日 Bing 背景图片的开关状态，捕获并记录异步操作中的异常
  Future<void> setBingBg(bool isOpen) async {
    try {
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      if (_isBingBg != isOpen) {
        LogUtil.safeExecute(() async {
          await _prefs?.setBool('bingBg', isOpen); // 使用缓存的 SharedPreferences 实例
          _isBingBg = isOpen;
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知 UI 更新
        }, '设置每日 Bing 背景时出错');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置每日 Bing 背景时出错', e, stackTrace);
    }
  }

  // 检测并设置设备是否为 TV，捕获并记录异步操作中的异常
  Future<void> checkAndSetIsTV() async {
    try {
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      LogUtil.safeExecute(() async {
        bool deviceIsTV = await EnvUtil.isTV(); // 调用工具类检测是否为 TV
        if (_isTV != deviceIsTV) {
          _isTV = deviceIsTV;
          await _prefs?.setBool('isTV', _isTV); // 使用缓存的 SharedPreferences 实例
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知监听器更新界面
        }
        LogUtil.i('设备检测结果: 该设备${deviceIsTV ? "是" : "不是"}TV');
      }, '检测并设置设备为 TV 时出错');
    } catch (error, stackTrace) {
      LogUtil.logError('检测并设置设备为 TV 时出错', error, stackTrace);
    }
  }

  // 手动设置是否为 TV，捕获并记录异步操作中的异常
  Future<void> setIsTV(bool isTV) async {
    try {
      await _ensurePrefsInitialized(); // 确保 SharedPreferences 已初始化
      if (_isTV != isTV) {
        LogUtil.safeExecute(() async {
          _isTV = isTV;
          await _prefs?.setBool('isTV', _isTV);  // 使用缓存的 SharedPreferences 实例
          _shouldNotify = true; // 标记需要通知 UI
          _notifyIfNeeded(); // 通知监听器更新界面
        }, '手动设置 TV 状态时出错');
      }
    } catch (error, stackTrace) {
      LogUtil.logError('手动设置 TV 状态时出错', error, stackTrace);
    }
  }
}
