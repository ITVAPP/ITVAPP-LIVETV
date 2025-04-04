import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart'; 

// EnvUtil 类用于检测设备、环境、语言并提供资源地址
class EnvUtil {
  static const MethodChannel _channel = MethodChannel(Config.packagename); // 定义与原生通信的通道
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin(); // 静态实例化设备信息插件以提升性能

  // 判断是否为 TV 设备，优先调用原生方法，失败则用设备信息补充
  static Future<bool> isTV() async {
    try {
      LogUtil.d('通过 Platform Channel 调用 Android 原生方法判断设备'); 
      final bool isTV = await _channel.invokeMethod('isTV'); // 调用 Android 原生 isTV 方法
      LogUtil.d('Platform Channel返回: $isTV'); 
      if (isTV) return true; // 原生方法确认后直接返回

      LogUtil.d('通过 device_info_plus 判断设备'); 
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo; // 获取 Android 设备信息
        final isTVDevice = androidInfo.isPhysicalDevice && // 检查是否为物理设备且型号含 TV
                           (androidInfo.brand == 'Android' && androidInfo.model.contains('TV'));
        final hasLeanbackFeature = androidInfo.systemFeatures.contains('android.software.leanback'); // 检查 Leanback 特性
        LogUtil.d('通过 Android 设备信息判断是否为 TV: $isTVDevice'); 
        LogUtil.d('通过 Android 设备信息判断是否具有 Leanback 特性: $hasLeanbackFeature'); 
        return isTVDevice || hasLeanbackFeature; // 综合判断结果
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo; // 获取 iOS 设备信息
        final isTVDevice = iosInfo.model.contains('Apple TV'); // 检查是否为 Apple TV
        LogUtil.d('通过 iOS 设备信息判断是否为 Apple TV: $isTVDevice'); 
        return isTVDevice;
      }
      return false; // 其他平台默认非 TV
    } on PlatformException catch (e) {
      LogUtil.e('检测设备发生错误: ${e.message}');
      return false; // 平台异常时默认非 TV
    } catch (e) {
      LogUtil.e('检测设备发生未知错误: ${e.toString()}');
      return false; // 其他异常时默认非 TV
    }
  }

  static bool? _isMobile; // 缓存是否为移动设备的结果

  // 判断是否为移动设备并缓存结果
  static bool get isMobile {
    if (_isMobile != null) return _isMobile!; // 返回缓存结果以避免重复检测
    _isMobile = Platform.isAndroid || Platform.isIOS; // 检查平台是否为 Android 或 iOS
    return _isMobile!;
  }

  // 判断系统语言是否为中文
  static bool isChinese() {
    final systemLocale = PlatformDispatcher.instance.locale; // 获取系统语言环境
    bool isChinese = systemLocale.languageCode == 'zh'; // 检查语言代码是否为中文
    return isChinese;
  }

  static const String _baseHost = 'https://www.itvapp.net'; // 统一管理资源基础地址

  // 获取资源下载地址
  static String sourceDownloadHost() {
    return _baseHost; // 返回基础地址
  }

  // 获取版本发布地址
  static String sourceReleaseHost() {
    return _baseHost; // 返回基础地址
  }

  // 根据语言环境获取项目主页地址
  static String sourceHomeHost() {
    if (isChinese()) {
      return 'https://gitee.com/AMuMuSir/easy_tv_live'; // 中文环境返回 Gitee 地址
    } else {
      return 'https://github.com/aiyakuaile/easy_tv_live'; // 其他环境返回 GitHub 地址
    }
  }

  // 根据语言和区域获取默认视频频道地址
  static String videoDefaultChannelHost() {
    final locale = PlatformDispatcher.instance.locale; // 获取系统语言环境
    final languageCode = locale.languageCode; // 提取语言代码
    final countryCode = locale.countryCode; // 提取区域代码

    if (languageCode == 'zh' && (countryCode == 'CN' || countryCode == null)) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists_zh.m3u'; // 简体中文环境地址
    }
    if (languageCode == 'zh' && (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists2.m3u'; // 繁体中文环境地址
    }
    return 'https://cdn.itvapp.net/itvapp_live_tv/playlists3.m3u'; // 其他语言环境地址
  }

  // 获取版本检查地址
  static String checkVersionHost() {
    return Config.upgradeUrl; // 返回 config.dart 中定义的升级地址
  }

  // 判断设备是否支持硬件加速
  static Future<bool> isHardwareAccelerationEnabled() async {
    try {
      LogUtil.d('开始检测是否支持硬件加速');
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo; // 获取 Android 设备信息
        final isAndroid7OrAbove = androidInfo.version.sdkInt >= 24; // 检查是否为 Android 7.0 及以上
        LogUtil.d('Android SDK 版本: ${androidInfo.version.sdkInt}, 是否支持硬件加速: $isAndroid7OrAbove');
        return isAndroid7OrAbove;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo; // 获取 ipqOS 设备信息
        final deviceModel = iosInfo.utsname.machine ?? ''; // 获取设备型号
        final isIPhone6OrAbove = deviceModel.contains('iPhone') && 
            _parseIPhoneModelNumber(deviceModel) >= 7; // 检查是否为 iPhone 6 及以上
        LogUtil.d('iOS 设备型号: $deviceModel, 是否支持硬件加速: $isIPhone6OrAbove');
        return isIPhone6OrAbove;
      }
      LogUtil.d('非 Android 或 iOS 设备，默认不支持硬件加速');
      return false; // 其他平台默认不支持
    } on PlatformException catch (e) {
      LogUtil.e('检测硬件加速支持发生 PlatformException: ${e.message}');
      return false; // 平台异常时默认不支持
    } catch (e) {
      LogUtil.e('检测硬件加速支持发生未知错误: ${e.toString()}');
      return false; // 其他异常时默认不支持
    }
  }

  // 解析 iPhone 型号编号以判断硬件支持
  static int _parseIPhoneModelNumber(String model) {
    try {
      if (model.contains('iPhone')) {
        final parts = model.split('iPhone')[1].split(','); // 分割型号字符串
        final majorVersion = int.tryParse(parts[0]) ?? 0; // 提取主版本号
        return majorVersion;
      }
      return 0; // 非 iPhone 型号返回 0
    } catch (e) {
      LogUtil.e('解析 iPhone 型号失败: $model');
      return 0; // 解析失败返回 0
    }
  }
}
