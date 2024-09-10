import 'package:flutter/foundation.dart';
import 'package:sp_util/sp_util.dart';
import '../util/font_util.dart';
import '../util/env_util.dart'; // 导入用于检测设备的工具类

class ThemeProvider extends ChangeNotifier {
  String _fontFamily = 'system';
  double _textScaleFactor = 1.0;
  String _fontUrl = '';
  bool _isBingBg = false;
  bool _isTV = false; // 添加 isTV 变量

  String get fontFamily => _fontFamily;
  double get textScaleFactor => _textScaleFactor;
  String get fontUrl => _fontUrl;
  bool get isBingBg => _isBingBg;
  bool get isTV => _isTV; // 添加获取 isTV 的方法

  // 构造函数，在初始化时从缓存中加载数据
  ThemeProvider() {
    // 安全获取字体和缩放比例，确保初始化时没有空指针错误
    _fontFamily = SpUtil.getString('appFontFamily', defValue: 'system') ?? 'system';
    _fontUrl = SpUtil.getString('appFontUrl', defValue: '') ?? '';
    _textScaleFactor = SpUtil.getDouble('fontScale', defValue: 1.0) ?? 1.0;
    
    // 安全获取 Bing 背景的状态，避免初始化时获取到空值
    _isBingBg = SpUtil.getBool('bingBg') ?? false;
    _isTV = SpUtil.getBool('isTV') ?? false; // 从缓存中获取 isTV 的值

    // 如果字体不是系统默认字体，则加载自定义字体
    if (_fontFamily != 'system') {
      FontUtil().loadFont(_fontUrl, _fontFamily);
    }
  }

  // 设置字体相关的方法
  void setFontFamily(String fontFamilyName, [String fontFullUrl = '']) {
    SpUtil.putString('appFontFamily', fontFamilyName);
    SpUtil.putString('appFontUrl', fontFullUrl);
    _fontFamily = fontFamilyName;
    _fontUrl = fontFullUrl;
    notifyListeners(); // 通知监听器更新界面
  }

  // 设置文本缩放
  void setTextScale(double textScaleFactor) {
    SpUtil.putDouble('fontScale', textScaleFactor);
    _textScaleFactor = textScaleFactor;
    notifyListeners(); // 通知监听器更新界面
  }

  // 设置是否使用每日 Bing 背景，异步操作，确保存储成功后再更新状态
  Future<void> setBingBg(bool isOpen) async {
    await SpUtil.putBool('bingBg', isOpen);  // 异步存储 Bing 背景的状态
    _isBingBg = isOpen;  // 更新内部状态
    notifyListeners();  // 通知监听器更新界面
  }

  // 检测并设置设备是否为 TV
  Future<void> checkAndSetIsTV() async {
    bool deviceIsTV = await EnvUtil.isTV(); // 调用工具类检测是否为 TV
    _isTV = deviceIsTV;
    await SpUtil.putBool('isTV', _isTV); // 异步存储结果
    notifyListeners(); // 通知监听器更新界面
  }

  // 手动设置是否为 TV
  Future<void> setIsTV(bool isTV) async {
    _isTV = isTV;
    await SpUtil.putBool('isTV', _isTV);  // 异步存储状态
    notifyListeners(); // 通知监听器更新界面
  }
}
