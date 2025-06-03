import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/font_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// 主题管理类，负责字体、缩放比例、背景等个性化配置
class ThemeProvider extends ChangeNotifier {
  // 单例模式，确保全局唯一实例
  static final ThemeProvider _instance = ThemeProvider._internal();
  factory ThemeProvider() => _instance;

  // 私有属性，存储应用个性化设置
  late String _fontFamily; // 当前字体名称
  late double _textScaleFactor; // 文本缩放比例
  late bool _isLogOn; // 日志开关状态
  late String _fontUrl; // 字体资源 URL
  late bool _isTV; // 是否为 TV 设备

  // 标记初始化状态
  bool _isInitialized = false;

  // 私有构造函数，不自动触发初始化
  ThemeProvider._internal();

  // 公共 Getter 方法
  bool get isInitialized => _isInitialized;
  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => Config.bingBgEnabled;
  bool get isTV => _isTV;
  bool get isLogOn => _isLogOn;

  /// 初始化方法，加载用户设置并处理异常
  Future<void> initialize() async {
    if (_isInitialized) return; // 已初始化则跳过

    try {
      final Map<String, dynamic> settings = await _loadAllSettings(); // 加载所有设置
      _applySettings(settings); // 应用设置

      // 若字体非默认，加载字体并处理失败回退
      if (_fontFamily != Config.defaultFontFamily) {
        bool fontLoaded = await FontUtil().loadFont(_fontUrl, _fontFamily);
        if (!fontLoaded) {
          _fontFamily = Config.defaultFontFamily; // 回退到默认字体
          LogUtil.i('字体加载失败，回退至: ${Config.defaultFontFamily}');
        }
      }

      _isInitialized = true; // 标记初始化完成
      notifyListeners(); // 通知 UI 更新
    } catch (e, stackTrace) {
      LogUtil.logError('ThemeProvider 初始化失败', e, stackTrace);
    }
  }

  /// 批量加载用户个性化设置
  Future<Map<String, dynamic>> _loadAllSettings() async {
    // 使用 Future.wait 并行读取所有设置
    final List<dynamic> results = await Future.wait([
      Future(() => SpUtil.getString('appFontFamily', defValue: Config.defaultFontFamily)),
      Future(() => SpUtil.getString('appFontUrl', defValue: '')),
      Future(() => SpUtil.getDouble('fontScale', defValue: Config.defaultTextScaleFactor)),
      Future(() => SpUtil.getBool('isTV', defValue: false)),
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

  /// 应用设置到属性并配置日志
  void _applySettings(Map<String, dynamic> settings) {
    _fontFamily = settings['fontFamily'] ?? Config.defaultFontFamily;
    _fontUrl = settings['fontUrl'] ?? '';
    _textScaleFactor = settings['textScaleFactor'] ?? Config.defaultTextScaleFactor;
    _isTV = settings['isTV'] ?? false;
    _isLogOn = settings['isLogOn'] ?? Config.defaultLogOn;

    LogUtil.setDebugMode(_isLogOn); // 设置日志模式
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

  /// 设置日志开关并保存，处理异常
  Future<void> setLogOn(bool isOpen) async {
    try {
      if (_isLogOn != isOpen) {
        _isLogOn = isOpen;
        await SpUtil.putBool('LogOn', isOpen);
        LogUtil.setDebugMode(_isLogOn); // 更新日志状态
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置日志开关失败', e, stackTrace);
    }
  }

  /// 设置字体并保存，加载字体并处理异常
  Future<void> setFontFamily(String fontFamilyName, [String fontFullUrl = '']) async {
    try {
      if (_fontFamily != fontFamilyName || _fontUrl != fontFullUrl) {
        _fontFamily = fontFamilyName;
        _fontUrl = fontFullUrl;

        // 批量保存字体设置
        await Future.wait([
          SpUtil.putString('appFontFamily', fontFamilyName)!, // 修改：添加非空断言
          SpUtil.putString('appFontUrl', fontFullUrl)!, // 修改：添加非空断言
        ]);

        // 若非默认字体，加载并处理失败回退
        if (_fontFamily != Config.defaultFontFamily) {
          bool fontLoaded = await FontUtil().loadFont(_fontUrl, _fontFamily);
          if (!fontLoaded) {
            _fontFamily = Config.defaultFontFamily;
            await SpUtil.putString('appFontFamily', _fontFamily);
            LogUtil.i('字体加载失败，回退至: ${Config.defaultFontFamily}');
          }
        }

        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置字体失败', e, stackTrace);
    }
  }

  /// 设置文本缩放比例并保存，处理异常
  Future<void> setTextScale(double textScaleFactor) async {
    try {
      if (_textScaleFactor != textScaleFactor) {
        _textScaleFactor = textScaleFactor;
        await SpUtil.putDouble('fontScale', textScaleFactor);
        notifyListeners(); // 通知 UI 更新
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置文本缩放失败', e, stackTrace);
    }
  }

  /// 检测并设置 TV 设备状态，处理异常
  Future<void> checkAndSetIsTV() async {
    try {
      bool deviceIsTV = await EnvUtil.isTV(); // 检测设备类型
      if (_isTV != deviceIsTV) {
        await setIsTV(deviceIsTV); // 更新 TV 状态
      }
      LogUtil.i('设备检测: ${deviceIsTV ? "是" : "不是"}TV');
    } catch (error, stackTrace) {
      LogUtil.logError('检测 TV 设备失败', error, stackTrace);
    }
  }

  /// 手动设置 TV 状态并保存，处理异常
  Future<void> setIsTV(bool isTV) async {
    try {
      if (_isTV != isTV) {
        _isTV = isTV;
        await SpUtil.putBool('isTV', _isTV);
        notifyListeners(); // 通知 UI 更新
      }
    } catch (error, stackTrace) {
      LogUtil.logError('设置 TV 状态失败', error, stackTrace);
    }
  }
}
