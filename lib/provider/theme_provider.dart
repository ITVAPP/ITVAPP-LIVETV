import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/font_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// 主题管理类，管理字体、缩放比例和设备状态
class ThemeProvider extends ChangeNotifier {
  // 单例实例
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;

  // TV设备默认字体缩放比例
  static const double _tvDefaultTextScaleFactor = 1.1;
  
  // 主题设置属性
  late String _fontFamily; // 当前字体
  late double _textScaleFactor; // 文本缩放比例
  late bool _isLogOn; // 日志开关
  late String _fontUrl; // 字体资源 URL
  late bool _isTV; // TV 设备状态

  // 初始化状态
  bool _isInitialized = false;

  // Getter 方法
  bool get isInitialized => _isInitialized;
  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => Config.bingBgEnabled;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn;

  // 私有构造函数
  ThemeProvider._internal();

  /// 初始化主题设置
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final Map<String, dynamic> settings = await _loadAllSettings();
      _applySettings(settings);

      if (_fontFamily != Config.defaultFontFamily) {
        bool fontLoaded = await FontUtil().loadFont(_fontUrl, _fontFamily);
        if (!fontLoaded) {
          _fontFamily = Config.defaultFontFamily;
          LogUtil.i('字体加载失败，回退至默认字体');
        }
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e, stackTrace) {
      LogUtil.logError('初始化主题设置失败', e, stackTrace);
    }
  }

  /// 加载用户设置
  Future<Map<String, dynamic>> _loadAllSettings() async {
    // 先获取是否是TV设备的状态
    final bool isTV = SpUtil.getBool('isTV', defValue: false) ?? false;
    
    // 获取用户保存的字体缩放比例
    final double? savedTextScaleFactor = SpUtil.getDouble('fontScale');
    
    // 确定默认的文本缩放比例
    // 如果用户没有设置过字体大小（savedTextScaleFactor为null），且是TV设备，则使用1.1
    // 否则使用Config中定义的默认值（通常是1.0）
    final double defaultTextScaleFactor = (savedTextScaleFactor == null && isTV) 
        ? _tvDefaultTextScaleFactor 
        : Config.defaultTextScaleFactor;
    
    final List<dynamic> results = await Future.wait([
      Future(() => SpUtil.getString('appFontFamily', defValue: Config.defaultFontFamily)),
      Future(() => SpUtil.getString('appFontUrl', defValue: '')),
      Future(() => savedTextScaleFactor ?? defaultTextScaleFactor),
      Future(() => isTV),
      Future(() => SpUtil.getBool('LogOn', defValue: Config.defaultLogOn)),
    ]);
    
    return {
      'fontFamily': results[0],
      'fontUrl': results[1],
      'textScaleFactor': results[2],
      'isTV': results[3],
      'isLogOn': results[4],
    };
  }

  /// 应用用户设置
  void _applySettings(Map<String, dynamic> settings) {
    _fontFamily = settings['fontFamily'] ?? Config.defaultFontFamily;
    _fontUrl = settings['fontUrl'] ?? '';
    _textScaleFactor = settings['textScaleFactor'] ?? Config.defaultTextScaleFactor;
    _isTV = settings['isTV'] ?? false;
    _isLogOn = settings['isLogOn'] ?? Config.defaultLogOn;

    LogUtil.setDebugMode(_isLogOn);
    LogUtil.d(
      '配置信息:\n'
      '字体: $_fontFamily\n'
      '字体 URL: $_fontUrl\n'
      '文本缩放比例: $_textScaleFactor\n'
      'Bing 背景启用: ${Config.bingBgEnabled ? "启用" : "未启用"} (配置控制)\n'
      '是否为 TV: ${_isTV ? "是 TV 设备" : "不是 TV 设备"}\n'
      '日志开关状态: ${_isLogOn ? "已开启" : "已关闭"}'
    );
  }

  /// 设置并保存日志开关
  Future<void> setLogOn(bool isOpen) async {
    try {
      if (_isLogOn != isOpen) {
        _isLogOn = isOpen;
        await SpUtil.putBool('LogOn', isOpen);
        LogUtil.setDebugMode(_isLogOn);
        notifyListeners();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关失败', e, stackTrace);
    }
  }

  /// 设置并保存字体
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      if (_fontFamily != fontFamilyName || _fontUrl != fontFullUrl) {
        _fontFamily = fontFamilyName;
        _fontUrl = fontFullUrl;

        await Future.wait([
          SpUtil.putString('appFontFamily', fontFamilyName)!,
          SpUtil.putString('appFontUrl', fontFullUrl)!,
        ]);

        if (_fontFamily != Config.defaultFontFamily) {
          bool fontLoaded = await FontUtil().loadFont(_fontUrl, _fontFamily);
          if (!fontLoaded) {
            _fontFamily = Config.defaultFontFamily;
            await SpUtil.putString('appFontFamily', _fontFamily);
            LogUtil.i('字体加载失败，回退至默认字体');
          }
        }

        notifyListeners();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体失败', e, stackTrace);
    }
  }

  /// 设置并保存文本缩放比例
  Future<void> setTextScale(double textScaleFactor) async {
    try {
      if (_textScaleFactor != textScaleFactor) {
        _textScaleFactor = textScaleFactor;
        await SpUtil.putDouble('fontScale', textScaleFactor);
        notifyListeners();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放失败', e, stackTrace);
    }
  }

  /// 检测并设置 TV 设备状态
  Future<void> checkAndSetIsTV() async {
    try {
      bool deviceIsTV = await EnvUtil.isTV();
      
      // 获取当前保存的字体缩放设置
      final double? savedTextScaleFactor = SpUtil.getDouble('fontScale');
      
      // 如果检测到是TV设备，且用户从未设置过字体大小
      if (deviceIsTV && savedTextScaleFactor == null) {
        // 直接设置TV默认字体大小，但不保存到SP
        // 这样用户仍然可以在设置页面看到并修改
        if (_textScaleFactor != _tvDefaultTextScaleFactor) {
          _textScaleFactor = _tvDefaultTextScaleFactor;
          notifyListeners();
          LogUtil.i('TV设备首次启动，应用默认字体缩放比例: $_tvDefaultTextScaleFactor');
        }
      }
      
      if (_isTV != deviceIsTV) {
        await setIsTV(deviceIsTV);
      }
      LogUtil.i('设备检测: ${deviceIsTV ? "是" : "不是"}TV');
    } catch (error, stackTrace) {
      LogUtil.logError('检测 TV 设备状态失败', error, stackTrace);
    }
  }

  /// 设置并保存 TV 状态
  Future<void> setIsTV(bool isTV) async {
    try {
      if (_isTV != isTV) {
        _isTV = isTV;
        await SpUtil.putBool('isTV', _isTV);
        notifyListeners();
      }
    } catch (error, stackTrace) {
      LogUtil.logError('设置 TV 状态失败', error, stackTrace);
    }
  }
}
