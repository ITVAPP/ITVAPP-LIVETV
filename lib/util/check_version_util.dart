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

// 版本检查工具类，负责检测更新并提示用户
class CheckVersionUtil {
  static const version = Config.version; // 当前应用版本号
  static final versionHost = EnvUtil.checkVersionHost(); // 版本检查 API 地址
  static final downloadLink = EnvUtil.sourceDownloadHost(); // 应用下载链接基础 URL
  static final releaseLink = EnvUtil.sourceReleaseHost(); // 应用发布页面 URL
  static final homeLink = EnvUtil.sourceHomeHost(); // 应用主页 URL
  static VersionEntity? latestVersionEntity; // 存储最新版本信息
  static const String _lastPromptDateKey = 'lastPromptDate'; // 存储最后提示日期的键名
  static const int oneDayInMillis = 24 * 60 * 60 * 1000; // 一天的毫秒数

  // 保存最后一次提示日期到本地存储
  static Future<void> saveLastPromptDate() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString(); // 获取当前时间戳
      await SpUtil.putString(_lastPromptDateKey, timestamp); // 存储时间戳
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
      final lastPromptTimestamp = await getLastPromptDate(); // 获取最后提示时间
      if (lastPromptTimestamp == null) return true; // 无记录时允许提示
      final lastTime = int.parse(lastPromptTimestamp); // 解析时间戳
      final currentTime = DateTime.now().millisecondsSinceEpoch; // 当前时间戳
      return (currentTime - lastTime) >= oneDayInMillis; // 判断是否超过一天
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace); // 记录检查错误
      return false; // 异常时避免频繁提示
    }
  }

  // 检查最新版本并返回版本信息
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    latestVersionEntity = null; // 重置缓存，确保最新数据
    try {
      final res = await HttpUtil().getRequest(versionHost); // 请求版本检查 API
      if (res == null || res is! Map<String, dynamic>) {
        LogUtil.d('版本检查失败：JSON 地址无法访问或格式错误');
        return null; // 数据无效返回 null
      }

      final latestVersion = res['version'] as String?; // 提取版本号
      final latestMsg = res['changelog'] as String?; // 提取更新日志
      final downloadUrl = res['download_url'] as String?; // 提取下载链接

      if (latestVersion == null || latestMsg == null || downloadUrl == null) {
        LogUtil.d('版本检查失败：JSON 缺少必要字段或格式不标准');
        return null; // 字段缺失返回 null
      }

      if (latestVersion.compareTo(version) > 0) { // 比较版本号
        latestVersionEntity = VersionEntity(
          latestVersion: latestVersion,
          latestMsg: latestMsg,
          downloadUrl: downloadUrl,
        ); // 更新版本信息
        return latestVersionEntity; // 返回新版本实体
      } else {
        if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion); // 提示已是最新版本
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
    return DialogUtil.showCustomDialog(
      context,
      title: '${S.current.findNewVersion}🚀', // 提示发现新版本
      content: latestVersionEntity!.latestMsg, // 显示更新日志
      ShowUpdateButton: latestVersionEntity!.downloadUrl!, // 使用下载链接
      isDismissible: false, // 禁止外部关闭
    );
  }

  // 检查版本并根据情况弹出提示
  static checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      if (!isManual && !await shouldShowPrompt()) return; // 非手动检查且未超一天则跳过
      final res = await checkRelease(isShowLoading, isShowLatestToast); // 检查版本
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context); // 显示更新对话框
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink); // 非 Android 打开发布页
        }
        if (!isManual) await saveLastPromptDate(); // 自动检查时保存时间
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本时发生错误', e, stackTrace); // 记录检查错误
    }
  }

  // 在外部浏览器中打开 URL
  static launchBrowserUrl(String url) async {
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
}

// 版本信息实体类，存储版本相关数据
class VersionEntity {
  final String? latestVersion; // 最新版本号
  final String? latestMsg; // 更新日志
  final String? downloadUrl; // 下载链接

  VersionEntity({
    this.latestVersion,
    this.latestMsg,
    this.downloadUrl,
  }); // 构造函数初始化版本信息
}
