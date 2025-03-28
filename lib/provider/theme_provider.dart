import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import '../util/font_util.dart';
import '../util/env_util.dart';
import '../util/log_util.dart';
import '../config.dart';

/// 主题管理类，负责应用字体、缩放比例、背景等个性化配置
class ThemeProvider extends ChangeNotifier {
  // 使用单例模式，确保全局只有一个 ThemeProvider 实例
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;

  // 私有属性，存储应用的个性化设置
  late String _fontFamily; // 当前字体
  late double _textScaleFactor; // 当前文本缩放比例
  late bool _isLogOn; // 日志开关状态
  late bool _isBingBg; // 是否启用 Bing 背景
  late String _fontUrl; // 字体资源 URL
  late bool _isTV; // 是否为 TV 设备

  // 控制 UI 通知更新的标记，避免重复重绘
  bool _shouldNotify = false;

  // 标记是否完成初始化
  bool _isInitialized = false;

  // 私有构造函数，调用初始化方法
  ThemeProvider._internal() {
    initialize();
  }

  // 公共 Getter 方法
  bool get isInitialized => _isInitialized;
  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn;

  // 通知 UI 更新，仅在需要时调用以节省资源
  void _notifyIfNeeded() {
    if (_shouldNotify) {
      _shouldNotify = false; // 重置通知标记
      notifyListeners(); // 通知监听者 UI 更新
    }
  }

  /// 初始化方法，加载并应用用户保存的设置
  /// 捕获并记录初始化中的异常
  Future<void> initialize() async {
    if (_isInitialized) return; // 避免重复初始化
    
    try {
      final Map<String, dynamic> settings = await _loadAllSettings(); // 批量加载设置
      _applySettings(settings); // 应用加载的设置
      
      // 如果自定义字体非默认字体，则加载字体
      if (_fontFamily != Config.defaultFontFamily) {
        await FontUtil().loadFont(_fontUrl, _fontFamily);
      }

      _isInitialized = true; // 设置初始化完成标记
      notifyListeners(); // 通知监听者更新状态
    } catch (e, stackTrace) {
      LogUtil.logError('初始化 ThemeProvider 时出错', e, stackTrace);
    }
  }

  /// 批量加载用户的个性化设置
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

  /// 应用加载的设置到相应属性，并设置日志模式
  void _applySettings(Map<String, dynamic> settings) {
    _fontFamily = settings['fontFamily'] ?? Config.defaultFontFamily;
    _fontUrl = settings['fontUrl'] ?? '';
    _textScaleFactor = settings['textScaleFactor'] ?? Config.defaultTextScaleFactor;
    _isBingBg = settings['isBingBg'] ?? Config.defaultBingBg;
    _isTV = settings['isTV'] ?? false;
    _isLogOn = settings['isLogOn'] ?? Config.defaultLogOn;
    
    LogUtil.setDebugMode(_isLogOn); // 配置日志模式
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

  /// 设置日志开关状态并保存到本地存储，捕获异步操作中的异常
  Future<void> setLogOn(bool isOpen) async {
    try {
      if (_isLogOn != isOpen) {
        _isLogOn = isOpen;
        await SpUtil.putBool('LogOn', isOpen);
        LogUtil.setDebugMode(_isLogOn); // 更新日志模式
        _shouldNotify = true;
        _notifyIfNeeded();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关状态时出错', e, stackTrace);
    }
  }

  /// 设置字体并保存到本地存储，捕获异步操作中的异常
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      if (_fontFamily != fontFamilyName || _fontUrl != fontFullUrl) {
        _fontFamily = fontFamilyName;
        _fontUrl = fontFullUrl;
        
        await SpUtil.putString('appFontFamily', fontFamilyName);
        await SpUtil.putString('appFontUrl', fontFullUrl);
        
        _shouldNotify = true;
        _notifyIfNeeded();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体时出错', e, stackTrace);
    }
  }

  /// 设置文本缩放比例并保存到本地存储，捕获异步操作中的异常
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

  /// 设置 Bing 背景开关状态并保存到本地存储，捕获异步操作中的异常
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

  /// 检测设备是否为 TV 并保存状态，捕获异步操作中的异常
  Future<void> checkAndSetIsTV() async {
    try {
      bool deviceIsTV = await EnvUtil.isTV(); // 调用工具检测是否为 TV 设备
      if (_isTV != deviceIsTV) {
        await setIsTV(deviceIsTV);
      }
      LogUtil.i('设备检测结果: 该设备${deviceIsTV ? "是" : "不是"}TV');
    } catch (error, stackTrace) {
      LogUtil.logError('检测并设置设备为 TV 时出错', error, stackTrace);
    }
  }

  /// 手动设置设备为 TV，并捕获异步操作中的异常
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
