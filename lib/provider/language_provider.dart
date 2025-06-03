import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// 语言管理类，通过 ChangeNotifier 提供语言变更通知
class LanguageProvider with ChangeNotifier {
  // 单例模式，确保全局只有一个 LanguageProvider 实例
  static final LanguageProvider _instance = LanguageProvider._internal();
  factory LanguageProvider() => _instance;
  
  // 静态正则表达式，避免重复编译
  static final RegExp _languageCodeRegex = RegExp(r'^[a-zA-Z_]+$');
  
  // 当前的应用语言环境
  late Locale _currentLocale;
  
  // 是否已初始化语言环境
  bool _isInitialized = false;
  
  // 获取当前语言环境的 Getter 方法
  Locale get currentLocale => _currentLocale;
  
  // 私有构造函数，初始化单例并加载已保存的语言设置
  LanguageProvider._internal() {
    // 从系统窗口获取默认语言，若失败则设为英文
    _currentLocale = WidgetsBinding.instance.window.locale ?? const Locale('en');
    _loadSavedLanguage(); // 加载用户保存的语言设置
  }
  
  /// 创建 Locale 对象，统一处理语言代码和国家代码
  Locale _createLocale(String languageCode, [String? countryCode]) {
    // 若国家代码非空，则创建带国家代码的 Locale
    if (countryCode != null && countryCode.isNotEmpty) {
      return Locale(languageCode, countryCode);
    }
    return Locale(languageCode); // 否则仅使用语言代码
  }
  
  /// 异步加载已保存的语言设置
  Future<void> _loadSavedLanguage() async {
    if (_isInitialized) return; // 已初始化则跳过
    try {
      // 批量读取语言设置
      final List<String?> settings = await Future.wait([
        Future(() => SpUtil.getString('languageCode')),
        Future(() => SpUtil.getString('countryCode')),
      ]);
      
      final String? languageCode = settings[0];
      final String? countryCode = settings[1];
      
      if (languageCode != null && languageCode.isNotEmpty) {
        try {
          // 确保语言代码格式正确
          if (!_languageCodeRegex.hasMatch(languageCode)) {
            LogUtil.v('保存的语言代码格式错误: $languageCode，将使用系统默认');
            // 重置为系统默认
            _isInitialized = true;
            return;
          }
          
          // 若国家代码存在且无效，则忽略它
          if (countryCode != null && !_languageCodeRegex.hasMatch(countryCode)) {
            LogUtil.v('保存的国家代码格式错误: $countryCode，将忽略');
            countryCode = null;
          }
          
          // 若语言代码有效，恢复保存的语言环境
          Locale newLocale = _createLocale(languageCode, countryCode);
          if (newLocale.languageCode != _currentLocale.languageCode || 
              newLocale.countryCode != _currentLocale.countryCode) {
            _currentLocale = newLocale; // 更新语言环境
            notifyListeners(); // 通知监听者
          }
          LogUtil.v('语言加载成功: $languageCode${countryCode != null ? "_$countryCode" : ""}');
        } catch (e, stack) {
          LogUtil.logError('解析保存的语言设置失败', e, stack);
        }
      } else {
        LogUtil.v('未找到保存语言，使用系统默认');
      }
      _isInitialized = true; // 标记初始化完成
    } catch (e, stackTrace) {
      LogUtil.logError('加载语言设置失败', e, stackTrace); // 记录加载异常
      _isInitialized = true; // 即使失败也标记为已初始化，避免反复尝试
    }
  }
  
  /// 更改应用语言并保存到持久化存储
  /// [languageCode] 如 "en" 或 "zh_CN"
  Future<void> changeLanguage(String languageCode) async {
    // 验证语言代码格式是否有效
    if (languageCode.isEmpty || languageCode.length < 2 || !_languageCodeRegex.hasMatch(languageCode)) {
      LogUtil.v('语言代码无效: $languageCode');
      return;
    }
    
    try {
      Locale newLocale;
      String? effectiveCountryCode;
      
      if (languageCode.contains('_')) {
        // 解析带国家代码的语言格式
        final parts = languageCode.split('_');
        if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          newLocale = _createLocale(parts[0], parts[1]);
          effectiveCountryCode = parts[1];
        } else {
          LogUtil.v('语言代码格式错误: $languageCode');
          return;
        }
      } else {
        newLocale = _createLocale(languageCode); // 仅语言代码
      }
      
      // 仅当语言环境真正变化时才通知监听者
      if (newLocale.languageCode != _currentLocale.languageCode || 
          newLocale.countryCode != _currentLocale.countryCode) {
        _currentLocale = newLocale; // 更新语言环境
        notifyListeners(); // 通知监听者
        
        // 批量保存语言设置到持久化存储
        try {
          final List<Future<bool>> saveTasks = [
            SpUtil.putString('languageCode', _currentLocale.languageCode),
          ];
          
          if (effectiveCountryCode != null) {
            saveTasks.add(SpUtil.putString('countryCode', effectiveCountryCode));
          } else if (_currentLocale.countryCode != null) {
            saveTasks.add(SpUtil.putString('countryCode', _currentLocale.countryCode!));
          } else {
            saveTasks.add(SpUtil.remove('countryCode'));
          }
          
          await Future.wait(saveTasks);
          
          LogUtil.v('语言设置已保存: ${_currentLocale.languageCode}${_currentLocale.countryCode != null ? "_${_currentLocale.countryCode}" : ""}');
        } catch (e, stackTrace) {
          LogUtil.logError('保存语言设置失败', e, stackTrace); // 记录保存异常
        }
      } 
    } catch (e, stackTrace) {
      LogUtil.logError('更改语言设置失败', e, stackTrace); // 记录更改异常
    }
  }
}
