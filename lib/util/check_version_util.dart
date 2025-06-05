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

/// 语义化版本比较辅助类，仅内部使用
/// 不导出为公共API，避免破坏现有代码引用
class _SemanticVersion {
  final List<int> _version;
  final String _buildMetadata;
  final String _preReleaseIdentifier;
  final String _originalString;

  _SemanticVersion._(this._version, this._preReleaseIdentifier, this._buildMetadata, this._originalString);

  // 版本解析缓存，避免重复解析
  static final Map<String, _SemanticVersion?> _parseCache = {};
  static const int _maxCacheSize = 100; // 限制缓存大小

  /// 解析版本字符串为语义化版本对象
  static _SemanticVersion? parse(String versionString) {
    if (versionString.isEmpty) return null;
    
    // 检查缓存
    if (_parseCache.containsKey(versionString)) {
      return _parseCache[versionString];
    }
    
    // 缓存大小限制
    if (_parseCache.length >= _maxCacheSize) {
      _parseCache.clear();
    }
    
    // 移除可能的 'v' 前缀
    String cleanVersion = versionString;
    if (cleanVersion.startsWith('v') || cleanVersion.startsWith('V')) {
      cleanVersion = cleanVersion.substring(1);
    }
    
    // 处理构建元数据部分 (例如 1.2.3+456)
    String buildMetadata = '';
    if (cleanVersion.contains('+')) {
      final parts = cleanVersion.split('+');
      cleanVersion = parts[0];
      buildMetadata = parts.length > 1 ? parts[1] : '';
    }
    
    // 处理预发布标识符 (例如 1.2.3-alpha.1)
    String preReleaseIdentifier = '';
    if (cleanVersion.contains('-')) {
      final parts = cleanVersion.split('-');
      cleanVersion = parts[0];
      preReleaseIdentifier = parts.length > 1 ? parts[1] : '';
    }
    
    // 解析版本号段
    final segments = cleanVersion.split('.');
    final versionNumbers = <int>[];
    
    for (final segment in segments) {
      final num = int.tryParse(segment);
      if (num == null) {
        _parseCache[versionString] = null;
        return null; // 无效的版本号段
      }
      versionNumbers.add(num);
    }
    
    // 确保至少有主版本号
    if (versionNumbers.isEmpty) {
      _parseCache[versionString] = null;
      return null;
    }
    
    // 扩展到标准的三段式 (主.次.修订)
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
  
  /// 比较两个版本号
  /// 返回 -1 如果当前版本小于 other
  /// 返回 0 如果当前版本等于 other
  /// 返回 1 如果当前版本大于 other
  int compareTo(_SemanticVersion other) {
    // 先比较版本号段
    final minLength = _version.length < other._version.length ? _version.length : other._version.length;
    
    for (int i = 0; i < minLength; i++) {
      final comparison = _version[i].compareTo(other._version[i]);
      if (comparison != 0) return comparison;
    }
    
    // 如果前面的段都相同，较长的版本号较大
    if (_version.length != other._version.length) {
      return _version.length.compareTo(other._version.length);
    }
    
    // 版本号相同时，比较预发布标识符
    // 没有预发布标识符的版本大于有预发布标识符的版本
    if (_preReleaseIdentifier.isEmpty && other._preReleaseIdentifier.isNotEmpty) {
      return 1;
    }
    
    if (_preReleaseIdentifier.isNotEmpty && other._preReleaseIdentifier.isEmpty) {
      return -1;
    }
    
    if (_preReleaseIdentifier != other._preReleaseIdentifier) {
      return _preReleaseIdentifier.compareTo(other._preReleaseIdentifier);
    }
    
    // 构建元数据不影响版本优先级
    return 0;
  }
  
  @override
  String toString() => _originalString;
}

// 版本检查工具类，负责检测更新并提示用户
class CheckVersionUtil {
  // 静态常量，仅计算一次，提高性能
  static const String version = Config.version; // 当前应用版本号
  static const String _lastPromptDateKey = 'lastPromptDate'; // 存储最后提示日期的键名
  static const int oneDayInMillis = 24 * 60 * 60 * 1000; // 一天的毫秒数

  // 延迟初始化的静态变量，避免重复计算
  static late final String versionHost = EnvUtil.checkVersionHost(); // 版本检查 API 地址
  static late final String releaseLink = EnvUtil.sourceReleaseHost(); // 应用发布页面 URL
  
  static VersionEntity? latestVersionEntity; // 存储最新版本信息
  static bool isForceUpdate = false; // 标记是否为强制更新状态

  // 检查版本并返回是否需要更新的缓存变量
  static bool? _cachedForceUpdateState;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5); // 缓存有效期5分钟

  // 保存最后一次提示日期到本地存储
  static Future<void> saveLastPromptDate() async {
    try {
      // 在强制更新模式下不保存日期，确保每次打开都提示
      if (isForceUpdate) {
        LogUtil.d('强制更新模式下不保存提示日期');
        return;
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString(); // 获取当前时间戳
      await SpUtil.putString(_lastPromptDateKey, timestamp); // 存储时间戳
      LogUtil.d('已保存最后提示日期: $timestamp');
    } catch (e, stackTrace) {
      LogUtil.logError('保存最后提示日期失败', e, stackTrace); // 记录保存错误
    }
  }

  // 获取最后一次提示日期
  static Future<String?> getLastPromptDate() async {
    try {
      final timestamp = SpUtil.getString(_lastPromptDateKey); // 获取存储的时间戳
      if (timestamp != null && timestamp.isNotEmpty && int.tryParse(timestamp) != null) {
        return timestamp; // 返回有效时间戳
      }
      if (timestamp != null) await SpUtil.remove(_lastPromptDateKey); // 清除无效数据
      return null; // 无有效记录返回 null
    } catch (e, stackTrace) {
      LogUtil.logError('获取最后提示日期失败', e, stackTrace); // 记录获取错误
      return null;
    }
  }

  // 检查是否超过一天未提示更新
  static Future<bool> shouldShowPrompt() async {
    try {
      // 在强制更新模式下始终返回 true
      if (isForceUpdate) {
        LogUtil.d('强制更新模式下始终显示更新提示');
        return true;
      }
      
      final lastPromptTimestamp = await getLastPromptDate(); // 获取最后提示时间
      if (lastPromptTimestamp == null) return true; // 无记录时允许提示
      
      final lastTime = int.parse(lastPromptTimestamp); // 解析时间戳
      final currentTime = DateTime.now().millisecondsSinceEpoch; // 当前时间戳
      final shouldShow = (currentTime - lastTime) >= oneDayInMillis; // 判断是否超过一天
      
      // 只在需要显示时记录日志，减少I/O操作
      if (shouldShow) {
        LogUtil.d('检查更新提示间隔: 上次时间=$lastPromptTimestamp, 当前时间=$currentTime, 应该显示=$shouldShow');
      }
      
      return shouldShow;
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace); // 记录检查错误
      return false; // 异常时避免频繁提示
    }
  }
  
  /// 辅助方法：比较两个版本号，判断第一个是否小于第二个
  /// 使用语义化版本比较，如果无法解析版本号，则回退到原有字符串比较
  static bool _isVersionLessThan(String v1, String v2) {
    final version1 = _SemanticVersion.parse(v1);
    final version2 = _SemanticVersion.parse(v2);
    
    // 如果任一版本解析失败，回退到原有的字符串比较逻辑
    if (version1 == null || version2 == null) {
      return v1.compareTo(v2) < 0; // 原始代码使用的方式
    }
    
    return version1.compareTo(version2) < 0;
  }
  
  /// 辅助方法：判断两个版本号是否相等
  /// 使用语义化版本比较，如果无法解析版本号，则回退到原有字符串比较
  static bool _isVersionEqual(String v1, String v2) {
    // 快速路径：如果字符串完全相同，直接返回true
    if (v1 == v2) return true;
    
    final version1 = _SemanticVersion.parse(v1);
    final version2 = _SemanticVersion.parse(v2);
    
    // 如果任一版本解析失败，回退到原有的字符串比较
    if (version1 == null || version2 == null) {
      return v1 == v2; // 原始代码使用的方式
    }
    
    return version1.compareTo(version2) == 0;
  }

  // 检查最新版本并返回版本信息 - 优化并发请求
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    latestVersionEntity = null; // 重置缓存，确保最新数据
    isForceUpdate = false; // 重置强制更新标志
    _cachedForceUpdateState = null; // 重置强制更新状态缓存
    
    try {
      LogUtil.d('开始检查版本更新: 主地址=$versionHost');
      
      // 获取备用地址
      final backupHost = EnvUtil.checkVersionBackupHost();
      
      // 并发请求主地址和备用地址
      Map<String, dynamic>? res;
      
      if (backupHost != null && backupHost.isNotEmpty) {
        // 使用 Future.any 获取最快的成功响应
        final futures = <Future<Map<String, dynamic>?>>[];
        
        // 主地址请求
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
        
        // 备用地址请求
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
        
        // 等待第一个成功的响应
        try {
          // 使用 Future.any 等待第一个完成的请求
          res = await Future.any(futures.map((future) => 
            future.then((value) {
              if (value != null) return value;
              throw Exception('无效响应');
            })
          ));
        } catch (e) {
          // 如果都失败，尝试按顺序获取结果
          final results = await Future.wait(futures, eagerError: false);
          res = results.firstWhere((r) => r != null, orElse: () => null);
        }
      } else {
        // 只有主地址，直接请求
        res = await HttpUtil().getRequest(versionHost);
      }
      
      // 检查响应有效性
      if (res == null || res is! Map<String, dynamic>) {
        LogUtil.d('版本检查失败：所有地址都无法访问或格式错误');
        return null; // 数据无效返回 null
      }

      final latestVersion = res['version'] as String?; // 提取版本号
      final latestMsg = res['changelog'] as String?; // 提取更新日志
      final downloadUrl = res['download_url'] as String?; // 提取下载链接
      final backupDownloadUrl = res['backup_download_url'] as String?; // 提取备用下载链接
      final minSupportedVersion = res['min_supported_version'] as String?; // 提取最低支持版本
      
      LogUtil.d('获取到版本信息: 最新版本=$latestVersion, 当前版本=$version, 最低支持版本=$minSupportedVersion');

      if (latestVersion == null || latestMsg == null || downloadUrl == null) {
        LogUtil.d('版本检查失败：JSON 缺少必要字段或格式不标准');
        return null; // 字段缺失返回 null
      }

      // 检查是否强制更新 - 当本地版本低于最低支持版本时
      if (minSupportedVersion != null && minSupportedVersion.isNotEmpty) {
        // 使用改进的语义化版本比较，替代原有的简单字符串比较
        if (_isVersionLessThan(version, minSupportedVersion)) {
          isForceUpdate = true;
          _cachedForceUpdateState = true;
          _cacheTime = DateTime.now();
          LogUtil.d('检测到强制更新：当前版本 $version 低于最低支持版本 $minSupportedVersion');
        }
      }

      // 版本号不相同时提示更新（不管是高于还是低于，保持原有行为）
      // 使用改进的语义化版本比较，替代原有的简单字符串比较
      if (!_isVersionEqual(latestVersion, version)) {
        LogUtil.d('检测到版本不同: 当前=$version, 最新=$latestVersion');
        latestVersionEntity = VersionEntity(
          latestVersion: latestVersion,
          latestMsg: latestMsg,
          downloadUrl: downloadUrl,
          backupDownloadUrl: backupDownloadUrl,
          minSupportedVersion: minSupportedVersion,
        ); // 更新版本信息
        return latestVersionEntity; // 返回新版本实体
      } else {
        if (isShowLatestToast) {
          LogUtil.d('当前已是最新版本');
          EasyLoading.showToast(S.current.latestVersion); // 提示已是最新版本
        }
        return null; // 无更新返回 null
      }
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace); // 记录检查错误
      return null; // 异常时返回 null
    }
  }

  // 显示版本更新对话框
  static Future<bool?> showUpdateDialog(BuildContext context) async {
    if (latestVersionEntity == null) return null; // 无新版本时返回 null
    
    // 增加强制更新的内容前缀
    String content = latestVersionEntity!.latestMsg ?? '';
    if (isForceUpdate) {
      content = "⚠️ $S.current.oldVersion \n\n$content";
    }
    
    return DialogUtil.showCustomDialog(
      context,
      title: '${S.current.findNewVersion}🚀', // 提示发现新版本
      content: content, // 显示更新日志
      ShowUpdateButton: latestVersionEntity!.downloadUrl!, // 使用下载链接
      isDismissible: !isForceUpdate, // 强制更新时禁止点击外部关闭
    );
  }

  // 检查版本并根据情况弹出提示
  static Future<bool> checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      if (!isManual && !await shouldShowPrompt()) {
        LogUtil.d('未满足更新提示条件，跳过版本检查'); 
        return false; // 非手动检查且未超一天则跳过
      }
      
      final res = await checkRelease(isShowLoading, isShowLatestToast); // 检查版本
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context); // 显示更新对话框
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink); // 非 Android 打开发布页
        }
        
        // 非强制更新且非手动检查时保存提示日期
        if (!isManual && !isForceUpdate) {
          await saveLastPromptDate();
          LogUtil.d('非强制更新：已保存最后提示日期');
        }
        
        return true; // 有更新返回 true
      }
      return false; // 无更新返回 false
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本时发生错误', e, stackTrace); // 记录检查错误
      return false; // 异常时返回 false
    }
  }

  // 在外部浏览器中打开 URL
  static Future<void> launchBrowserUrl(String url) async {
    try {
      final uri = Uri.tryParse(url); // 解析 URL
      if (uri == null || !uri.isAbsolute) {
        LogUtil.logError('无效的URL格式: URL=$url', null, null);
        return; // URL 无效则退出
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication); // 打开外部浏览器
    } catch (e, stackTrace) {
      LogUtil.logError('打开浏览器失败: URL=$url', e, stackTrace); // 记录打开错误
    }
  }
  
  // 检查是否处于强制更新状态，带缓存机制
  static bool isInForceUpdateState() {
    // 如果有缓存且缓存未过期，直接返回缓存值
    if (_cachedForceUpdateState != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedForceUpdateState!;
      }
    }
    
    // 缓存过期或不存在，返回当前状态并更新缓存
    _cachedForceUpdateState = isForceUpdate;
    _cacheTime = DateTime.now();
    return isForceUpdate; // 返回强制更新标志
  }
}

// 版本信息实体类，存储版本相关数据
class VersionEntity {
  final String? latestVersion; // 最新版本号
  final String? latestMsg; // 更新日志
  final String? downloadUrl; // 下载链接
  final String? backupDownloadUrl; // 备用下载链接
  final String? minSupportedVersion; // 最低支持版本

  VersionEntity({
    this.latestVersion,
    this.latestMsg,
    this.downloadUrl,
    this.backupDownloadUrl,
    this.minSupportedVersion,
  }); // 构造函数初始化版本信息
}
