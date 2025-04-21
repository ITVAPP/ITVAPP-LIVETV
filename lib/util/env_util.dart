import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

// EnvUtil 类用于检测设备、环境、语言并提供资源地址
class EnvUtil {
  static const MethodChannel _channel = MethodChannel(Config.packagename); // 与原生通信的通道
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin(); // 设备信息插件实例

  // 缓存系统语言环境，避免重复获取
  static final Locale _systemLocale = PlatformDispatcher.instance.locale;

  // 缓存平台类型，减少重复判断
  static final bool _isAndroid = Platform.isAndroid;
  static final bool _isIOS = Platform.isIOS;

  // 判断是否为 TV 设备，优先原生方法，失败则用设备信息
  static Future<bool> isTV() async {
    try {
      LogUtil.d('通过 Platform Channel 调用 Android 原生方法判断设备');
      final bool isTV = await _channel.invokeMethod<bool>('isTV') ?? false; // 调用原生方法判断
      LogUtil.d('Platform Channel返回: $isTV');
      if (isTV) return true;

      LogUtil.d('通过 device_info_plus 判断设备');
      if (_isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo; // 获取 Android 设备信息
        final isTVDevice = androidInfo.isPhysicalDevice && // 检查物理设备且型号含 TV
            (androidInfo.brand == 'Android' && androidInfo.model.contains('TV'));
        final hasLeanbackFeature = androidInfo.systemFeatures.contains('android.software.leanback'); // 检查 Leanback 特性
        LogUtil.d('Android 判断是否为 TV: $isTVDevice, Leanback 特性: $hasLeanbackFeature');
        return isTVDevice || hasLeanbackFeature;
      } else if (_isIOS) {
        final iosInfo = await _deviceInfo.iosInfo; // 获取 iOS 设备信息
        final isTVDevice = iosInfo.model.contains('Apple TV'); // 检查是否为 Apple TV
        LogUtil.d('iOS 判断是否为 Apple TV: $isTVDevice');
        return isTVDevice;
      }
      return false; // 其他平台默认非 TV
    } on PlatformException catch (e) {
      LogUtil.e('检测设备发生错误: ${e.message}');
      return false; // 异常时默认非 TV
    } catch (e) {
      LogUtil.e('检测设备发生未知错误: ${e.toString()}');
      return false;
    }
  }

  static bool? _isMobile; // 缓存是否为移动设备

  // 初始化并缓存 isMobile，避免重复计算
  static final bool isMobile = _initIsMobile();

  // 静态初始化 isMobile
  static bool _initIsMobile() {
    _isMobile = _isAndroid || _isIOS; // 判断是否为 Android 或 iOS
    return _isMobile!;
  }

  // 判断系统语言是否为中文
  static bool isChinese() {
    return _systemLocale.languageCode == 'zh'; // 检查语言代码是否为中文
  }

  static const String _baseHost = 'https://www.itvapp.net'; // 资源基础地址

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
    return isChinese()
        ? 'https://gitee.com/AMuMuSir/easy_tv_live' // 中文返回 Gitee
        : 'https://github.com/aiyakuaile/easy_tv_live'; // 其他返回 GitHub
  }

  // 根据语言和区域获取默认视频频道地址
  static String videoDefaultChannelHost() {
    final languageCode = _systemLocale.languageCode; // 提取语言代码
    final countryCode = _systemLocale.countryCode; // 提取区域代码
    if (languageCode == 'zh' && (countryCode == 'CN' || countryCode == null)) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists_zh.m3u'; // 简体中文地址
    }
    if (languageCode == 'zh' && (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')) {
      return 'https://cdn.itvapp.net/itvapp_live_tv/playlists2.m3u'; // 繁体中文地址
    }
    return 'https://cdn.itvapp.net/itvapp_live_tv/playlists3.m3u'; // 其他语言地址
  }

  // 获取版本检查地址
  static String checkVersionHost() {
    return Config.upgradeUrl; // 返回配置中的升级地址
  }
  
  // 获取版本检查备用地址
  static String? checkVersionBackupHost() {
    return Config.backupUpgradeUrl; // 返回配置中的备用升级地址
  }

  // 判断设备是否支持硬件加速
  static Future<bool> isHardwareAccelerationEnabled() async {
    try {
      LogUtil.d('开始检测是否支持硬件加速');
      if (_isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo; // 获取 Android 设备信息
        final isAndroid7OrAbove = androidInfo.version.sdkInt >= 24; // 检查 Android 7.0 及以上
        LogUtil.d('Android SDK: ${androidInfo.version.sdkInt}, 支持硬件加速: $isAndroid7OrAbove');
        return isAndroid7OrAbove;
      } else if (_isIOS) {
        final iosInfo = await _deviceInfo.iosInfo; // 获取 iOS 设备信息
        final deviceModel = iosInfo.utsname.machine ?? ''; // 获取设备型号
        final isIPhone6OrAbove = deviceModel.contains('iPhone') &&
            _parseIPhoneModelNumber(deviceModel) >= 7; // 检查 iPhone 6 及以上
        LogUtil.d('iOS 型号: $deviceModel, 支持硬件加速: $isIPhone6OrAbove');
        return isIPhone6OrAbove;
      }
      LogUtil.d('非 Android/iOS，默认不支持硬件加速');
      return false; // 其他平台默认不支持
    } on PlatformException catch (e) {
      LogUtil.e('检测硬件加速发生 PlatformException: ${e.message}');
      return false; // 异常时默认不支持
    } catch (e) {
      LogUtil.e('检测硬件加速发生未知错误: ${e.toString()}');
      return false;
    }
  }

  // 解析 iPhone 型号编号以判断硬件支持
  static int _parseIPhoneModelNumber(String model) {
    /// 解析 iPhone 型号，如 "iPhone10,3" 返回 10
    /// - 参数: model - 设备型号字符串
    /// - 返回: 主版本号，失败返回 0
    /// - 限制: 仅支持标准格式，未来型号可能需调整
    try {
      if (model.contains('iPhone')) {
        final parts = model.split('iPhone')[1].split(','); // 分割型号字符串
        final majorVersion = int.tryParse(parts[0]) ?? 0; // 提取主版本号
        return majorVersion;
      }
      return 0; // 非 iPhone 返回 0
    } catch (e) {
      LogUtil.e('解析 iPhone 型号失败: $model');
      return 0; // 解析失败返回 0
    }
  }
}
