import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// 语言管理类，提供语言变更通知
class LanguageProvider with ChangeNotifier {
  // 单例实例
  static final LanguageProvider _instance = LanguageProvider._internal();
  factory LanguageProvider() => _instance;
  
  // 正则表达式验证语言代码
  static final RegExp _languageCodeRegex = RegExp(r'^[a-zA-Z_]+$');
  
  // 当前语言环境
  late Locale _currentLocale;
  
  // 语言初始化标志
  bool _isInitialized = false;
  
  // 获取当前语言环境
  Locale get currentLocale => _currentLocale;
  
  // 私有构造函数，加载保存的语言设置
  LanguageProvider._internal() {
    _currentLocale = WidgetsBinding.instance.window.locale ?? const Locale('en');
    _loadSavedLanguage(); // 加载保存的语言设置
  }
  
  /// 创建 Locale 对象
  Locale _createLocale(String languageCode, [String? countryCode]) {
    if (countryCode != null && countryCode.isNotEmpty) {
      return Locale(languageCode, countryCode);
    }
    return Locale(languageCode);
  }
  
  /// 加载保存的语言设置
  Future<void> _loadSavedLanguage() async {
    if (_isInitialized) return;
    try {
      final List<String?> settings = await Future.wait([
        Future(() => SpUtil.getString('languageCode')),
        Future(() => SpUtil.getString('countryCode')),
      ]);
      
      final String? languageCode = settings[0];
      String? countryCode = settings[1];
      
      if (languageCode != null && languageCode.isNotEmpty) {
        try {
          if (!_languageCodeRegex.hasMatch(languageCode)) {
            LogUtil.v('语言代码格式错误: $languageCode，使用系统默认');
            _isInitialized = true;
            return;
          }
          
          if (countryCode != null && !_languageCodeRegex.hasMatch(countryCode)) {
            LogUtil.v('国家代码格式错误: $countryCode，忽略');
            countryCode = null;
          }
          
          Locale newLocale = _createLocale(languageCode, countryCode);
          if (newLocale.languageCode != _currentLocale.languageCode || 
              newLocale.countryCode != _currentLocale.countryCode) {
            _currentLocale = newLocale;
            notifyListeners();
          }
          LogUtil.v('语言加载成功: $languageCode${countryCode != null ? "_$countryCode" : ""}');
        } catch (e, stack) {
          LogUtil.logError('加载语言设置失败', e, stack);
        }
      } else {
        LogUtil.v('未找到保存语言，使用系统默认');
      }
      _isInitialized = true;
    } catch (e, stackTrace) {
      LogUtil.logError('加载语言设置失败', e, stackTrace);
      _isInitialized = true;
    }
  }
  
  /// 更改并保存语言设置
  Future<void> changeLanguage(String languageCode) async {
    if (languageCode.isEmpty || languageCode.length < 2 || !_languageCodeRegex.hasMatch(languageCode)) {
      LogUtil.v('语言代码无效: $languageCode');
      return;
    }
    
    try {
      Locale newLocale;
      String? effectiveCountryCode;
      
      if (languageCode.contains('_')) {
        final parts = languageCode.split('_');
        if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          newLocale = _createLocale(parts[0], parts[1]);
          effectiveCountryCode = parts[1];
        } else {
          LogUtil.v('语言代码格式错误: $languageCode');
          return;
        }
      } else {
        newLocale = _createLocale(languageCode);
      }
      
      if (newLocale.languageCode != _currentLocale.languageCode || 
          newLocale.countryCode != _currentLocale.countryCode) {
        _currentLocale = newLocale;
        notifyListeners();
        
        try {
          final List<Future<bool>> saveTasks = [
            SpUtil.putString('languageCode', _currentLocale.languageCode)!,
          ];
          
          if (effectiveCountryCode != null) {
            saveTasks.add(SpUtil.putString('countryCode', effectiveCountryCode)!);
          } else if (_currentLocale.countryCode != null) {
            saveTasks.add(SpUtil.putString('countryCode', _currentLocale.countryCode!)!);
          } else {
            saveTasks.add(SpUtil.remove('countryCode')!);
          }
          
          await Future.wait(saveTasks);
          
          LogUtil.v('语言设置已保存: ${_currentLocale.languageCode}${_currentLocale.countryCode != null ? "_${_currentLocale.countryCode}" : ""}');
        } catch (e, stackTrace) {
          LogUtil.logError('保存语言设置失败', e, stackTrace);
        }
      } 
    } catch (e, stackTrace) {
      LogUtil.logError('更改语言设置失败', e, stackTrace);
    }
  }
}
