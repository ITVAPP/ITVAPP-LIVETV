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
    _fontFamily = SpUtil.getString('appFontFamily', defValue: 'system')!;
    _fontUrl = SpUtil.getString('appFontUrl', defValue: '')!;
    _textScaleFactor = SpUtil.getDouble('fontScale', defValue: 1.0)!;
    _isBingBg = SpUtil.getBool('bingBg', defValue: false)!;
    _isTV = SpUtil.getBool('isTV', defValue: false)!; // 从缓存中获取 isTV 的值
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

  // 设置是否使用每日 Bing 背景
  void setBingBg(bool isOpen) {
    SpUtil.putBool('bingBg', isOpen);
    _isBingBg = isOpen;
    notifyListeners(); // 通知监听器更新界面
  }

  // 检测并设置设备是否为 TV
  Future<void> checkAndSetIsTV() async {
    bool deviceIsTV = await EnvUtil.isTV(); // 调用工具类检测是否为 TV
    _isTV = deviceIsTV;
    SpUtil.putBool('isTV', _isTV); // 将结果保存到缓存
    notifyListeners(); // 通知监听器更新界面
  }

  // 手动设置是否为 TV
  void setIsTV(bool isTV) {
    _isTV = isTV;
    SpUtil.putBool('isTV', _isTV);
    notifyListeners(); // 通知监听器更新界面
  }
}
