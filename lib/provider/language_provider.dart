import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import '../util/log_util.dart';

/// 语言管理类，通过 ChangeNotifier 提供语言变更通知
class LanguageProvider with ChangeNotifier {
  // 单例模式，确保全局只有一个 LanguageProvider 实例
  static final LanguageProvider _instance = LanguageProvider._internal();
  factory LanguageProvider() => _instance;

  // 当前的应用语言环境
  late Locale _currentLocale;

  // 是否已初始化语言环境
  bool _isInitialized = false;

  // 获取当前语言环境的 Getter 方法
  Locale get currentLocale => _currentLocale;

  // 私有构造函数，初始化单例并加载已保存的语言设置
  LanguageProvider._internal() {
    // 从系统窗口获取默认语言环境，如果获取失败则默认为英文
    _currentLocale = WidgetsBinding.instance.window.locale ?? const Locale('en');
    _loadSavedLanguage(); // 尝试加载用户已保存的语言设置
  }

  /// 异步加载已保存的语言设置
  Future<void> _loadSavedLanguage() async {
    // 如果已初始化过，则直接返回
    if (_isInitialized) return;

    try {
      // 从持久化存储中读取语言代码和国家代码
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');

      // 如果存在语言代码，尝试恢复语言环境
      if (languageCode != null && languageCode.isNotEmpty) {
        if (countryCode != null && countryCode.isNotEmpty) {
          // 如果国家代码存在，则使用完整的 Locale
          _currentLocale = Locale(languageCode, countryCode);
        } else {
          // 仅有语言代码时，使用简化的 Locale
          _currentLocale = Locale(languageCode);
        }
        // 通知所有监听者语言已更改
        notifyListeners();
        LogUtil.v('语言加载成功: $languageCode${countryCode != null ? "_$countryCode" : ""}');
      } else {
        // 未找到已保存的语言设置，使用系统默认语言
        LogUtil.v('未找到已保存的语言设置，使用系统默认语言');
      }
      _isInitialized = true; // 标记已完成初始化
    } catch (e, stackTrace) {
      // 捕获异常并记录日志
      LogUtil.logError('从 SpUtil 加载语言设置时发生错误', e, stackTrace);
    }
  }

  /// 更改应用语言设置并保存到持久化存储
  Future<void> changeLanguage(String languageCode) async {
    // 验证语言代码是否有效
    if (languageCode.isEmpty || languageCode.length < 2) {
      LogUtil.v('语言代码无效: $languageCode');
      return;
    }

    try {
      // 如果语言代码包含下划线，尝试解析为完整的 Locale
      if (languageCode.contains('_')) {
        final parts = languageCode.split('_');
        if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          _currentLocale = Locale(parts[0], parts[1]);
        }
      } else {
        // 否则仅使用语言代码创建 Locale
        _currentLocale = Locale(languageCode);
      }

      // 通知所有监听者语言已更改
      notifyListeners();
      LogUtil.v('语言已更改为: $languageCode');

      try {
        // 将语言设置保存到持久化存储
        if (_currentLocale.countryCode?.isNotEmpty == true) {
          // 如果国家代码存在，则保存国家代码
          await SpUtil.putString('countryCode', _currentLocale.countryCode!);
        } else {
          // 否则移除已保存的国家代码
          await SpUtil.remove('countryCode');
        }
        // 保存语言代码
        await SpUtil.putString('languageCode', _currentLocale.languageCode);

        LogUtil.v('语言设置已保存到 SpUtil');
      } catch (e, stackTrace) {
        // 捕获保存时的异常并记录日志
        LogUtil.logError('保存语言设置到 SpUtil 时发生错误', e, stackTrace);
      }
    } catch (e, stackTrace) {
      // 捕获更改语言设置的异常并记录日志
      LogUtil.logError('更改语言设置时发生错误', e, stackTrace);
    }
  }
}
