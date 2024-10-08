import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import '../util/log_util.dart';

class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = WidgetsBinding.instance.window.locale ?? const Locale('en'); // 默认使用系统语言

  // 获取当前语言
  Locale get currentLocale => _currentLocale;

  // 构造函数中使用 Future.microtask 延迟加载已保存的语言设置
  LanguageProvider() {
    Future.microtask(() => _loadSavedLanguage());
  }

  // 从 SpUtil 加载已保存的语言设置
  Future<void> _loadSavedLanguage() async {
    try {
      LogUtil.safeExecute(() async {
        String? languageCode = SpUtil.getString('languageCode'); // 获取已保存的语言代码
        String? countryCode = SpUtil.getString('countryCode'); // 获取已保存的国家代码

        if (languageCode != null && languageCode.isNotEmpty) {
          // 检查并设置语言代码和国家代码
          if (countryCode != null && countryCode.isNotEmpty) {
            _currentLocale = Locale(languageCode, countryCode); // 设置包含国家代码的 Locale
          } else {
            _currentLocale = Locale(languageCode); // 设置仅包含语言代码的 Locale
          }
          notifyListeners(); // 通知监听器语言已加载
          LogUtil.v('语言加载成功: $languageCode${countryCode != null ? "_$countryCode" : ""}');
        } else {
          LogUtil.v('未找到已保存的语言设置，使用系统默认语言');
        }
      }, '加载已保存语言设置时发生错误');
    } catch (e, stackTrace) {
      LogUtil.logError('从 SpUtil 加载语言设置时发生错误', e, stackTrace);
    }
  }

  // 更改语言的方法
  Future<void> changeLanguage(String languageCode) async {
    LogUtil.safeExecute(() async {
      // 防御性编程：检查语言代码格式是否正确
      if (languageCode.isEmpty || languageCode.length < 2) {
        LogUtil.v('语言代码无效: $languageCode');
        return; // 如果语言代码不符合预期格式，则直接返回
      }

      if (languageCode.contains('_')) {
        // 如果语言代码包含下划线，如 'zh_CN'
        final parts = languageCode.split('_');
        if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          _currentLocale = Locale(parts[0], parts[1]); // 将 'zh_CN' 转换为 Locale('zh', 'CN')
        }
      } else {
        // 如果没有下划线，则直接使用语言代码，如 'en'
        _currentLocale = Locale(languageCode); // 直接使用语言代码
      }

      notifyListeners(); // 通知所有监听器，语言已更改
      LogUtil.v('语言已更改为: $languageCode');

      // 保存设置到 SpUtil
      try {
        SpUtil.putString('languageCode', _currentLocale.languageCode); // 保存语言代码
        if (_currentLocale.countryCode != null) {
          SpUtil.putString('countryCode', _currentLocale.countryCode!); // 保存国家代码
        } else {
          SpUtil.remove('countryCode'); // 如果没有国家代码，则移除
        }
        LogUtil.v('语言设置已保存到 SpUtil');
      } catch (e, stackTrace) {
        LogUtil.logError('保存语言设置到 SpUtil 时发生错误', e, stackTrace);
      }
    }, '更改语言设置时发生错误');
  }
}
