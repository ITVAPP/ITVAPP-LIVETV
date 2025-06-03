import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

// 检测设备、环境、语言并提供资源地址的工具类
class EnvUtil {
  // 与原生通信的通道
  static const MethodChannel _channel = MethodChannel(Config.packagename);
  // 设备信息插件实例
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // 缓存系统语言环境
  static final Locale _systemLocale = PlatformDispatcher.instance.locale;

  // 缓存平台类型
  static final bool _isAndroid = Platform.isAndroid;
  static final bool _isIOS = Platform.isIOS;

  // 缓存设备是否为 TV，仅缓存成功结果
  static bool? _cachedIsTV;
  // 缓存硬件加速支持状态，仅缓存成功结果
  static bool? _cachedIsHardwareAccelerationEnabled;

  // 判断设备是否为 TV，返回布尔值
  static Future<bool> isTV() async {
    if (_cachedIsTV != null) return _cachedIsTV!; // 返回缓存结果
    try {
      // 调用原生方法判断设备类型
      final bool isTV = await _channel.invokeMethod<bool>('isTV') ?? false;
      LogUtil.d('原生方法判断设备类型: $isTV');
      if (isTV) {
        _cachedIsTV = true;
        return true;
      }
      // 通过设备信息判断
      if (_isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final isTVDevice = androidInfo.isPhysicalDevice && (androidInfo.brand == 'Android' && androidInfo.model.contains('TV'));
        final hasLeanbackFeature = androidInfo.systemFeatures.contains('android.software.leanback');
        LogUtil.d('Android设备判断: TV=$isTVDevice, Leanback=$hasLeanbackFeature');
        final result = isTVDevice || hasLeanbackFeature;
        _cachedIsTV = result;
        return result;
      } else if (_isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final isTVDevice = iosInfo.model.contains('Apple TV');
        LogUtil.d('iOS设备判断: Apple TV=$isTVDevice');
        _cachedIsTV = isTVDevice;
        return isTVDevice;
      }
      _cachedIsTV = false;
      return false; // 其他平台默认非 TV
    } on PlatformException catch (e) {
      LogUtil.e('设备检测失败: ${e.message}');
      return false; // 异常时默认非 TV
    } catch (e) {
      LogUtil.e('设备检测未知错误: $e');
      return false;
    }
  }

  // 缓存是否为移动设备
  static bool? _isMobile;

  // 初始化并缓存移动设备状态
  static final bool isMobile = _initIsMobile();

  // 判断是否为 Android 或 iOS 设备
  static bool _initIsMobile() {
    _isMobile = _isAndroid || _isIOS;
    return _isMobile!;
  }

  // 判断系统语言是否为中文
  static bool isChinese() {
    return _systemLocale.languageCode == 'zh'; // 检查语言代码是否为 zh
  }

  // 资源基础地址
  static const String _baseHost = 'https://www.itvapp.net';

  // 获取资源下载地址
  static String sourceDownloadHost() {
    return _baseHost; // 返回资源基础地址
  }

  // 获取版本发布地址
  static String sourceReleaseHost() {
    return _baseHost; // 返回版本发布地址
  }

  // 根据语言环境获取项目主页地址
  static String sourceHomeHost() {
    return isChinese()
        ? 'https://gitee.com/AMuMuSir/easy_tv_live' // 中文返回 Gitee
        : 'https://github.com/aiyakuaile/easy_tv_live'; // 其他返回 GitHub
  }

  // 根据语言和区域获取默认视频频道地址
  static String videoDefaultChannelHost() {
    final languageCode = _systemLocale.languageCode;
    final countryCode = _systemLocale.countryCode;
    if (languageCode == 'zh' && (countryCode == 'CN' || countryCode == null)) {
      return Config.defaultPlaylistZhCN; // 简体中文地址
    }
    if (languageCode == 'zh' && (countryCode == 'TW' || countryCode == 'HK' || countryCode == 'MO')) {
      return Config.defaultPlaylistZhTW; // 繁体中文地址
    }
    return Config.defaultPlaylistOther; // 其他语言地址
  }

  // 获取版本检查地址
  static String checkVersionHost() {
    return Config.upgradeUrl; // 返回升级地址
  }

  // 获取版本检查备用地址
  static String? checkVersionBackupHost() {
    return Config.backupUpgradeUrl; // 返回备用升级地址
  }

  // 判断设备是否支持硬件加速
  static Future<bool> isHardwareAccelerationEnabled() async {
    if (_cachedIsHardwareAccelerationEnabled != null) return _cachedIsHardwareAccelerationEnabled!; // 返回缓存结果
    try {
      // 检测硬件加速支持
      if (_isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final isAndroid7OrAbove = androidInfo.version.sdkInt >= 24;
        LogUtil.d('Android SDK: ${androidInfo.version.sdkInt}, 硬件加速=$isAndroid7OrAbove');
        _cachedIsHardwareAccelerationEnabled = isAndroid7OrAbove;
        return isAndroid7OrAbove;
      } else if (_isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final deviceModel = iosInfo.utsname.machine ?? '';
        final isIPhone6OrAbove = deviceModel.contains('iPhone') &&
            _parseIPhoneModelNumber(deviceModel) >= 7;
        LogUtil.d('iOS型号: $deviceModel, 硬件加速=$isIPhone6OrAbove');
        _cachedIsHardwareAccelerationEnabled = isIPhone6OrAbove;
        return isIPhone6OrAbove;
      }
      LogUtil.d('非Android/iOS，默认不支持硬件加速');
      _cachedIsHardwareAccelerationEnabled = false;
      return false; // 其他平台默认不支持
    } on PlatformException catch (e) {
      LogUtil.e('硬件加速检测失败: ${e.message}');
      return false; // 异常时默认不支持
    } catch (e) {
      LogUtil.e('硬件加速检测未知错误: $e');
      return false;
    }
  }

  // 解析 iPhone 型号编号
  static int _parseIPhoneModelNumber(String model) {
    // 提取 iPhone 型号主版本号，如 iPhone10,3 返回 10
    try {
      if (model.contains('iPhone')) {
        final parts = model.split('iPhone')[1].split(',');
        final majorVersion = int.tryParse(parts[0]) ?? 0;
        return majorVersion;
      }
      return 0; // 非 iPhone 返回 0
    } catch (e) {
      LogUtil.e('解析 iPhone 型号失败: $model');
      return 0; // 解析失败返回 0
    }
  }
}
