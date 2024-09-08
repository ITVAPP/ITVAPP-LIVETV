import 'dart:io';  // 导入 dart 的平台检测库，用于识别操作系统
import 'dart:ui';  // 导入 dart 的 UI 库，用于获取系统语言环境

// EnvUtil 类用于提供设备、环境和语言的检测以及不同资源地址的获取
class EnvUtil {
  // _isMobile 用于缓存是否是移动设备的结果，初始值为 null
  static bool? _isMobile;

  // 判断是否为 TV 设备
  // 通过 Dart 的编译时常量环境变量来检查 'isTV' 是否为 true
  static bool isTV() {
    return const bool.fromEnvironment('isTV');
  }

  // 判断是否为移动设备
  // 根据平台判断是否为 Android 或 iOS，并缓存结果以便后续调用
  static bool get isMobile {
    if (_isMobile != null) return _isMobile!;  // 如果已检测过，直接返回缓存结果
    _isMobile = Platform.isAndroid || Platform.isIOS;  // 检测平台是否为 Android 或 iOS
    return _isMobile!;
  }

  // 判断系统语言是否为中文
  // 通过 PlatformDispatcher 获取当前系统语言环境，判断语言代码是否为 'zh'
  static bool isChinese() {
    final systemLocale = PlatformDispatcher.instance.locale;  // 获取系统当前语言环境
    bool isChinese = systemLocale.languageCode == 'zh';  // 判断语言代码是否为 'zh'
    return isChinese;  // 返回是否为中文
  }

  // 获取下载源的基础地址，用于下载资源
  static String sourceDownloadHost() {
    return 'https://www.itvapp.net'; 
  }

  // 获取发布版本的基础地址，用于查看项目发布的版本
  static String sourceReleaseHost() {
    return 'https://www.itvapp.net'; 
  }

  // 获取项目主页地址
  static String sourceHomeHost() {
    if (isChinese()) {
      return 'https://gitee.com/AMuMuSir/easy_tv_live';  // 中文环境返回 Gitee 项目地址
    } else {
      return 'https://github.com/aiyakuaile/easy_tv_live';  // 其他环境返回 GitHub 项目地址
    }
  }

  // 获取默认视频频道地址
  static String videoDefaultChannelHost() {
    if (isChinese()) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists_zh.m3u';  // 中文环境返回 Gitee 原始资源地址
    } else {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists.m3u';  // 其他环境返回 GitHub 原始资源地址
    }
  }

  // 获取版本检查地址，用于检测软件更新
  static String checkVersionHost() {
    return 'https://api.github.com/repos/aiyakuaile/easy_tv_live/releases/latest'; 
  }

  // 获取字体资源的基础地址
  static String fontLink() {
    if (isChinese()) {
      return 'https://gitee.com/AMuMuSir/easy_tv_font/raw/main';  // 中文环境返回 Gitee 字体地址
    } else {
      return 'https://raw.githubusercontent.com/aiyakuaile/easy_tv_font/main';  // 其他环境返回 GitHub 字体地址
    }
  }

  // 获取字体下载地址
  static String fontDownloadLink() {
    if (isChinese()) {
      return 'https://gitee.com/AMuMuSir/easy_tv_font/releases/download/fonts';  // 中文环境返回 Gitee 字体下载地址
    } else {
      return 'https://raw.githubusercontent.com/aiyakuaile/easy_tv_font/main';  // 其他环境返回 GitHub 字体下载地址
    }
  }
}
