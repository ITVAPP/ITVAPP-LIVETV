import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:device_info_plus/device_info_plus.dart';

// EnvUtil 类用于提供设备、环境和语言的检测以及不同资源地址的获取
class EnvUtil {
  static const MethodChannel _channel = MethodChannel('net.itvapp.isTV'); // 使用 net.itvapp.isTV 作为 Channel 名称

  // 判断是否为 TV 设备，调用 Android 平台的 isTV 方法
  static Future<bool> isTV() async {
    try {
      final bool isTV = await _channel.invokeMethod('isTV'); // 通过 Platform Channel 调用 Android 原生 isTV 方法
      LogUtil.d('通过 Platform Channel 调用 Android 原生 isTV 方法: $isTV'); // 输出调试信息
      if (isTV) return true; // 如果原生判断为 TV，直接返回 true

      // 使用 device_info_plus 获取设备信息
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // 判断品牌和型号
        final isTVDevice = androidInfo.isPhysicalDevice &&
                           (androidInfo.brand == 'Android' &&
                            androidInfo.model.contains('TV'));
        // 检查设备是否具有 Leanback 特性
        final hasLeanbackFeature = androidInfo.systemFeatures.contains('android.software.leanback');
        LogUtil.d('通过 Android 设备信息判断是否为 TV: $isTVDevice'); // 输出调试信息
        LogUtil.d('通过 Android 设备信息判断是否具有 Leanback 特性: $hasLeanbackFeature'); // 输出调试信息
        return isTVDevice || hasLeanbackFeature;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // 检查设备型号是否为 Apple TV
        final isTVDevice = iosInfo.model.contains('Apple TV');
        LogUtil.d('通过 iOS 设备信息判断是否为 Apple TV: $isTVDevice'); // 输出调试信息
        return isTVDevice;
      }
      return false; // 对于其他平台默认返回 false
    } on PlatformException catch (e) {
      LogUtil.e('检测设备发生错误: ${e.message}');
      return false; // 出现异常时返回 false，默认不是电视
    } catch (e) {
      LogUtil.e('检测设备发生未知错误: ${e.toString()}');
      return false; // 处理其他异常，默认返回 false
    }
  }

  // _isMobile 用于缓存是否是移动设备的结果，初始值为 null
  static bool? _isMobile;

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

  // 获取默认视频频道地址，扩展支持简体中文、繁体中文和其他语言
  static String videoDefaultChannelHost() {
    final locale = PlatformDispatcher.instance.locale;  // 获取系统当前语言环境
    final languageCode = locale.languageCode;  // 获取语言代码
    final countryCode = locale.countryCode;  // 获取区域代码

    // 简体中文环境
    if (languageCode == 'zh' && (countryCode == 'CN' || countryCode == null)) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists_zh.m3u';
    }

    // 繁体中文环境
    if (languageCode == 'zh' && (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists2.m3u';
    }

    // 其他语言环境
    return 'https://cdn.itvapp.net/itvapp_live_tv/playlists3.m3u';
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
