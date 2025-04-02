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

class CheckVersionUtil {
  static const version = Config.version;  // 当前应用版本号
  static final versionHost = EnvUtil.checkVersionHost();  // 版本检查的API地址
  static final downloadLink = EnvUtil.sourceDownloadHost();  // 应用下载链接的基础URL
  static final releaseLink = EnvUtil.sourceReleaseHost();  // 应用发布页面URL
  static final homeLink = EnvUtil.sourceHomeHost();  // 应用主页URL
  static VersionEntity? latestVersionEntity;  // 存储最新的版本信息
  static const String _lastPromptDateKey = 'lastPromptDate';  // 存储最后一次提示日期的键名
  static const int oneDayInMillis = 24 * 60 * 60 * 1000;  // 一天的毫秒数，用于时间间隔计算

  // 保存最后一次弹出提示的日期到本地存储
  static Future<void> saveLastPromptDate() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();  // 获取当前时间戳字符串
      await SpUtil.putString(_lastPromptDateKey, timestamp);  // 存储时间戳
    } catch (e, stackTrace) {
      LogUtil.logError('保存最后提示日期失败', e, stackTrace);  // 记录保存失败的错误日志
    }
  }

  // 从本地存储获取最后一次弹出提示的日期
  static Future<String?> getLastPromptDate() async {
    try {
      final timestamp = SpUtil.getString(_lastPromptDateKey);  // 获取存储的时间戳
      if (timestamp != null && timestamp.isNotEmpty && int.tryParse(timestamp) != null) {
        return timestamp;  // 返回有效的时间戳
      }
      if (timestamp != null) await SpUtil.remove(_lastPromptDateKey);  // 清除无效数据
      return null;  // 返回null表示无有效记录
    } catch (e, stackTrace) {
      LogUtil.logError('获取最后提示日期失败', e, stackTrace);  // 记录获取失败的错误日志
      return null;
    }
  }

  // 检查是否超过一天未提示更新
  static Future<bool> shouldShowPrompt() async {
    try {
      final lastPromptTimestamp = await getLastPromptDate();  // 获取最后提示时间
      if (lastPromptTimestamp == null) return true;  // 无记录时允许提示

      final lastTime = int.parse(lastPromptTimestamp);  // 解析时间戳为整数
      final currentTime = DateTime.now().millisecondsSinceEpoch;  // 获取当前时间戳
      return (currentTime - lastTime) >= oneDayInMillis;  // 判断是否超过一天
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace);  // 记录检查失败的错误日志
      return true;  // 默认允许提示以确保用户体验
    }
  }

  // 检查最新版本并返回版本信息
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    if (latestVersionEntity != null) return latestVersionEntity;  // 返回缓存的版本信息，避免重复请求

    try {
      final res = await HttpUtil().getRequest(versionHost);  // 请求版本检查API
      if (res == null) return null;  // 请求失败返回null

      final latestVersion = res['tag_name'] is String ? res['tag_name'] as String : null;  // 提取版本号
      final latestMsg = res['body'] is String ? res['body'] as String : null;  // 提取更新日志

      if (latestVersion != null && latestVersion.compareTo(version) > 0) {
        latestVersionEntity = VersionEntity(latestVersion: latestVersion, latestMsg: latestMsg);  // 更新最新版本信息
        return latestVersionEntity;  // 返回新版本实体
      } else {
        latestVersionEntity = null;  // 重置缓存，表示无新版本
        if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion);  // 提示已是最新版本
      }
      return null;  // 无新版本返回null
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace);  // 记录版本检查失败的错误日志
      return null;
    }
  }

  // 显示版本更新对话框
  static Future<bool?> showUpdateDialog(BuildContext context) async {
    if (latestVersionEntity == null) return null;  // 无新版本时返回null

    return DialogUtil.showCustomDialog(
      context,
      title: '${S.current.findNewVersion}🚀',  // 对话框标题，提示发现新版本
      content: CheckVersionUtil.latestVersionEntity!.latestMsg,  // 显示更新日志
      ShowUpdateButton: 'https://github.com/aiyakuaile/easy_tv_live/releases/download/2.7.7/easy.apk',  // 下载链接
      isDismissible: false,  // 禁止点击外部关闭对话框
    );
  }

  // 检查版本并根据情况弹出更新提示
  static checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      if (!isManual && !await shouldShowPrompt()) return;  // 自动检查时若未超一天则跳过

      final res = await checkRelease(isShowLoading, isShowLatestToast);  // 检查最新版本
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context);  // 显示更新对话框
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink);  // 非Android设备打开发布页面
        }
        if (!isManual) await saveLastPromptDate();  // 自动检查时保存提示时间
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本时发生错误', e, stackTrace);  // 记录检查过程中的错误日志
    }
  }

  // 在外部浏览器中打开指定URL
  static launchBrowserUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);  // 使用外部应用打开链接
    } catch (e, stackTrace) {
      LogUtil.logError('打开浏览器失败: URL=$url', e, stackTrace);  // 记录打开失败的错误日志
    }
  }
}

// 版本信息实体类，用于存储版本号和更新日志
class VersionEntity {
  final String? latestVersion;  // 最新版本号
  final String? latestMsg;  // 更新日志内容

  VersionEntity({this.latestVersion, this.latestMsg});  // 构造函数，初始化版本信息
}
