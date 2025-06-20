import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 版本比较辅助类
class _SemanticVersion {
  final List<int> _version;
  final String _buildMetadata;
  final String _preReleaseIdentifier;
  final String _originalString;

  _SemanticVersion._(this._version, this._preReleaseIdentifier, this._buildMetadata, this._originalString);

  static final Map<String, _SemanticVersion?> _parseCache = {};
  static const int _maxCacheSize = 100;

  /// 解析版本字符串为语义化版本对象
  static _SemanticVersion? parse(String versionString) {
    if (versionString.isEmpty) return null;
    
    if (_parseCache.containsKey(versionString)) {
      return _parseCache[versionString];
    }
    
    if (_parseCache.length >= _maxCacheSize) {
      _parseCache.clear();
    }
    
    String cleanVersion = versionString;
    if (cleanVersion.startsWith('v') || cleanVersion.startsWith('V')) {
      cleanVersion = cleanVersion.substring(1);
    }
    
    String buildMetadata = '';
    if (cleanVersion.contains('+')) {
      final parts = cleanVersion.split('+');
      cleanVersion = parts[0];
      buildMetadata = parts.length > 1 ? parts[1] : '';
    }
    
    String preReleaseIdentifier = '';
    if (cleanVersion.contains('-')) {
      final parts = cleanVersion.split('-');
      cleanVersion = parts[0];
      preReleaseIdentifier = parts.length > 1 ? parts[1] : '';
    }
    
    final segments = cleanVersion.split('.');
    final versionNumbers = <int>[];
    
    for (final segment in segments) {
      final num = int.tryParse(segment);
      if (num == null) {
        _parseCache[versionString] = null;
        return null;
      }
      versionNumbers.add(num);
    }
    
    if (versionNumbers.isEmpty) {
      _parseCache[versionString] = null;
      return null;
    }
    
    while (versionNumbers.length < 3) {
      versionNumbers.add(0);
    }
    
    final result = _SemanticVersion._(
      versionNumbers, 
      preReleaseIdentifier, 
      buildMetadata,
      versionString
    );
    
    _parseCache[versionString] = result;
    return result;
  }
  
  /// 比较版本号：返回-1（小于）、0（等于）、1（大于）
  int compareTo(_SemanticVersion other) {
    final minLength = _version.length < other._version.length ? _version.length : other._version.length;
    
    for (int i = 0; i < minLength; i++) {
      final comparison = _version[i].compareTo(other._version[i]);
      if (comparison != 0) return comparison;
    }
    
    if (_version.length != other._version.length) {
      return _version.length.compareTo(other._version.length);
    }
    
    if (_preReleaseIdentifier.isEmpty && other._preReleaseIdentifier.isNotEmpty) {
      return 1;
    }
    
    if (_preReleaseIdentifier.isNotEmpty && other._preReleaseIdentifier.isEmpty) {
      return -1;
    }
    
    if (_preReleaseIdentifier != other._preReleaseIdentifier) {
      return _preReleaseIdentifier.compareTo(other._preReleaseIdentifier);
    }
    
    return 0;
  }
  
  @override
  String toString() => _originalString;
}

/// 版本检查工具类，管理更新检测与用户提示
class CheckVersionUtil {
  static const String version = Config.version;
  static const String _lastPromptDateKey = 'lastPromptDate';
  static const int oneDayInMillis = 24 * 60 * 60 * 1000;

  static late final String versionHost = EnvUtil.checkVersionHost();
  static late final String releaseLink = EnvUtil.sourceReleaseHost();
  
  static VersionEntity? latestVersionEntity;
  static bool isForceUpdate = false;

  static bool? _cachedForceUpdateState;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// 保存最后提示日期到本地存储
  static Future<void> saveLastPromptDate() async {
    try {
      if (isForceUpdate) {
        LogUtil.d('强制更新：跳过保存提示日期');
        return;
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      await SpUtil.putString(_lastPromptDateKey, timestamp);
      LogUtil.d('保存提示日期: $timestamp');
    } catch (e, stackTrace) {
      LogUtil.logError('保存提示日期失败', e, stackTrace);
    }
  }

  /// 获取最后提示日期
  static Future<String?> getLastPromptDate() async {
    try {
      final timestamp = SpUtil.getString(_lastPromptDateKey);
      if (timestamp != null && timestamp.isNotEmpty && int.tryParse(timestamp) != null) {
        return timestamp;
      }
      if (timestamp != null) await SpUtil.remove(_lastPromptDateKey);
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取提示日期失败', e, stackTrace);
      return null;
    }
  }

  /// 检查是否需显示更新提示（间隔一天）
  static Future<bool> shouldShowPrompt() async {
    try {
      if (isForceUpdate) {
        LogUtil.d('强制更新：始终显示提示');
        return true;
      }
      
      final lastPromptTimestamp = await getLastPromptDate();
      if (lastPromptTimestamp == null) return true;
      
      final lastTime = int.parse(lastPromptTimestamp);
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final shouldShow = (currentTime - lastTime) >= oneDayInMillis;
      
      if (shouldShow) {
        LogUtil.d('提示间隔检查: 上次=$lastPromptTimestamp, 当前=$currentTime, 需显示=$shouldShow');
      }
      
      return shouldShow;
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace);
      return false;
    }
  }
  
  /// 比较版本号：v1是否小于v2
  static bool _isVersionLessThan(String v1, String v2) {
    final version1 = _SemanticVersion.parse(v1);
    final version2 = _SemanticVersion.parse(v2);
    
    if (version1 == null || version2 == null) {
      return v1.compareTo(v2) < 0;
    }
    
    return version1.compareTo(version2) < 0;
  }
  
  /// 判断版本号是否相等
  static bool _isVersionEqual(String v1, String v2) {
    if (v1 == v2) return true;
    
    final version1 = _SemanticVersion.parse(v1);
    final version2 = _SemanticVersion.parse(v2);
    
    if (version1 == null || version2 == null) {
      return v1 == v2;
    }
    
    return version1.compareTo(version2) == 0;
  }

  /// 检查最新版本并返回版本信息
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    latestVersionEntity = null;
    isForceUpdate = false;
    _cachedForceUpdateState = null;
    
    try {
      LogUtil.d('开始版本检查: 主地址=$versionHost');
      
      final backupHost = EnvUtil.checkVersionBackupHost();
      
      Map<String, dynamic>? res;
      
      if (backupHost != null && backupHost.isNotEmpty) {
        final futures = <Future<Map<String, dynamic>?>>[];
        
        futures.add(
          HttpUtil().getRequest(versionHost).then((result) {
            if (result != null && result is Map<String, dynamic>) {
              LogUtil.d('主地址请求成功');
              return result;
            }
            throw Exception('主地址响应无效');
          }).catchError((e) {
            LogUtil.d('主地址请求失败: $e');
            return null;
          })
        );
        
        futures.add(
          HttpUtil().getRequest(backupHost).then((result) {
            if (result != null && result is Map<String, dynamic>) {
              LogUtil.d('备用地址请求成功');
              return result;
            }
            throw Exception('备用地址响应无效');
          }).catchError((e) {
            LogUtil.d('备用地址请求失败: $e');
            return null;
          })
        );
        
        try {
          res = await Future.any(futures.map((future) => 
            future.then((value) {
              if (value != null) return value;
              throw Exception('无效响应');
            })
          ));
        } catch (e) {
          final results = await Future.wait(futures, eagerError: false);
          res = results.firstWhere((r) => r != null, orElse: () => null);
        }
      } else {
        res = await HttpUtil().getRequest(versionHost);
      }
      
      if (res == null || res is! Map<String, dynamic>) {
        LogUtil.d('版本检查失败：响应无效');
        return null;
      }

      final latestVersion = res['version'] as String?;
      final latestMsg = res['changelog'] as String?;
      final downloadUrl = res['download_url'] as String?;
      final backupDownloadUrl = res['backup_download_url'] as String?;
      final minSupportedVersion = res['min_supported_version'] as String?;
      
      LogUtil.d('版本信息: 最新=$latestVersion, 当前=$version, 最低支持=$minSupportedVersion');

      if (latestVersion == null || latestMsg == null || downloadUrl == null) {
        LogUtil.d('版本检查失败：缺少必要字段');
        return null;
      }

      if (minSupportedVersion != null && minSupportedVersion.isNotEmpty) {
        if (_isVersionLessThan(version, minSupportedVersion)) {
          isForceUpdate = true;
          _cachedForceUpdateState = true;
          _cacheTime = DateTime.now();
          LogUtil.d('强制更新: 当前=$version, 最低支持=$minSupportedVersion');
        }
      }

      if (!_isVersionEqual(latestVersion, version)) {
        LogUtil.d('版本不同: 当前=$version, 最新=$latestVersion');
        latestVersionEntity = VersionEntity(
          latestVersion: latestVersion,
          latestMsg: latestMsg,
          downloadUrl: downloadUrl,
          backupDownloadUrl: backupDownloadUrl,
          minSupportedVersion: minSupportedVersion,
        );
        return latestVersionEntity;
      } else {
        if (isShowLatestToast) {
          LogUtil.d('已是最新版本');
          EasyLoading.showToast(S.current.latestVersion);
        }
        return null;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace);
      return null;
    }
  }

  /// 显示版本更新对话框
  static Future<bool?> showUpdateDialog(BuildContext context) async {
    if (latestVersionEntity == null) return null;
    
    String content = latestVersionEntity!.latestMsg ?? '';
    if (isForceUpdate) {
      content = "⚠️ ${S.current.oldVersion} \n\n$content";
    }
    
    return DialogUtil.showCustomDialog(
      context,
      title: '${S.current.findNewVersion}🚀',
      content: content,
      ShowUpdateButton: latestVersionEntity!.downloadUrl!,
      isDismissible: !isForceUpdate,
    );
  }

  /// 检查版本并根据情况弹出提示
  static Future<bool> checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      if (!isManual && !await shouldShowPrompt()) {
        LogUtil.d('未达提示间隔，跳过检查');
        return false;
      }
      
      final res = await checkRelease(isShowLoading, isShowLatestToast);
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context);
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink);
        }
        
        if (!isManual && !isForceUpdate) {
          await saveLastPromptDate();
          LogUtil.d('非强制更新：保存提示日期');
        }
        
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查错误', e, stackTrace);
      return false;
    }
  }

  /// 在外部浏览器打开URL
  static Future<void> launchBrowserUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.isAbsolute) {
        LogUtil.e('无效URL: $url');
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stackTrace) {
      LogUtil.logError('打开浏览器失败: URL=$url', e, stackTrace);
    }
  }
  
  /// 检查是否为强制更新状态（带缓存）
  static bool isInForceUpdateState() {
    if (_cachedForceUpdateState != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedForceUpdateState!;
      }
    }
    
    _cachedForceUpdateState = isForceUpdate;
    _cacheTime = DateTime.now();
    return isForceUpdate;
  }
}

/// 版本信息实体类
class VersionEntity {
  final String? latestVersion; /// 最新版本号
  final String? latestMsg; /// 更新日志
  final String? downloadUrl; /// 下载链接
  final String? backupDownloadUrl; /// 备用下载链接
  final String? minSupportedVersion; /// 最低支持版本

  VersionEntity({
    this.latestVersion,
    this.latestMsg,
    this.downloadUrl,
    this.backupDownloadUrl,
    this.minSupportedVersion,
  });
}
