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
  static final versionHost = EnvUtil.checkVersionHost();  // 版本检查的API地址（改为 final，避免重复计算）
  static final downloadLink = EnvUtil.sourceDownloadHost();  // 应用下载链接的基础URL（改为 final）
  static final releaseLink = EnvUtil.sourceReleaseHost();  // 应用发布页面URL（改为 final）
  static final homeLink = EnvUtil.sourceHomeHost();  // 应用主页URL（改为 final）
  static VersionEntity? latestVersionEntity;  // 存储最新的版本信息
  static const String _lastPromptDateKey = 'lastPromptDate';  // 存储键名常量
  static const int oneDayInMillis = 24 * 60 * 60 * 1000;  // 一天的毫秒数，提高可读性

  // 保存最后一次弹出提示的日期
  static Future<void> saveLastPromptDate() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();  // 使用时间戳字符串
      await SpUtil.putString(_lastPromptDateKey, timestamp);
    } catch (e, stackTrace) {
      LogUtil.logError('保存最后提示日期失败', e, stackTrace);  // 错误处理
    }
  }

  // 获取最后一次弹出提示的日期
  static Future<String?> getLastPromptDate() async {
    try {
      final timestamp = SpUtil.getString(_lastPromptDateKey);  // 获取时间戳字符串
      if (timestamp != null && timestamp.isNotEmpty && int.tryParse(timestamp) != null) {
        return timestamp;
      }
      // 如果不是有效的时间戳，清除数据
      if (timestamp != null) {
        await SpUtil.remove(_lastPromptDateKey);
      }
      return null;  // 如果格式不正确，返回 null
    } catch (e, stackTrace) {
      LogUtil.logError('获取最后提示日期失败', e, stackTrace);  // 错误处理
      return null;
    }
  }

  // 检查是否超过一天未提示
  static Future<bool> shouldShowPrompt() async {
    try {
      final lastPromptTimestamp = await getLastPromptDate();  // 获取最后一次提示时间戳
      if (lastPromptTimestamp == null) return true;  // 如果没有记录，表示从未提示过，直接返回 true

      final lastTime = int.parse(lastPromptTimestamp);  // 解析时间戳
      final currentTime = DateTime.now().millisecondsSinceEpoch;  // 获取当前时间戳

      // 检查是否超过1天，使用常量提高可读性
      return (currentTime - lastTime) >= oneDayInMillis;  // 使用毫秒计算更精确
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace);  // 错误处理
      return true;  // 发生错误时，默认返回 true，确保用户仍会收到提示
    }
  }

  // 检查最新版本，并返回版本信息
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    // 如果已有版本信息，则直接返回，避免重复请求
    if (latestVersionEntity != null) return latestVersionEntity;

    try {
      final res = await HttpUtil().getRequest(versionHost);  // 发送网络请求检查最新版本
      if (res == null) return null;  // 请求结果为空，直接返回 null

      // 增加类型检查，避免类型转换异常
      final latestVersion = res['tag_name'] is String ? res['tag_name'] as String : null;
      final latestMsg = res['body'] is String ? res['body'] as String : null;

      if (latestVersion != null && latestVersion.compareTo(version) > 0) {
        // 如果发现新版本，更新 latestVersionEntity
        latestVersionEntity = VersionEntity(latestVersion: latestVersion, latestMsg: latestMsg);
        return latestVersionEntity;  // 返回最新版本信息
      } else {
        // 如果当前已是最新版本，重置 latestVersionEntity 并提示
        latestVersionEntity = null;  // 重置缓存，避免使用过时数据
        if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion);  // 显示最新版本提示
      }
      return null;  // 没有新版本，返回 null
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace);  // 错误处理
      return null;  // 网络请求失败时返回 null
    }
  }

  // 显示版本更新的对话框
  static Future<bool?> showUpdateDialog(BuildContext context) async {
    if (latestVersionEntity == null) return null;

    // 显示更新对话框，包含新版本信息和下载按钮
    return DialogUtil.showCustomDialog(
      context,
      title: '${S.current.findNewVersion}🚀',
      content: CheckVersionUtil.latestVersionEntity!.latestMsg,
      ShowUpdateButton: 'https://github.com/aiyakuaile/easy_tv_live/releases/download/2.7.7/easyTV-2.7.7.apk',  // 传递下载链接
      isDismissible: false,  // 禁止点击对话框外部关闭
    );
  }

  // 检查版本并弹出提示
  static checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      // 如果是自动检查并且一天内已经提示过，则不再弹窗
      if (!isManual && !await shouldShowPrompt()) {
        return;
      }

      // 检查版本，如果有新版本，则弹出更新提示
      final res = await checkRelease(isShowLoading, isShowLatestToast);
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context);  // 弹出更新对话框
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink);  // 如果用户选择更新，并且不是 Android 设备，打开更新链接
        }

        // 如果是自动检查，弹窗后保存提示时间
        if (!isManual) {
          await saveLastPromptDate();  // 保存弹窗提示的时间
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本时发生错误', e, stackTrace);  // 错误处理
    }
  }

  // 在浏览器中打开指定 URL
  static launchBrowserUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);  // 使用外部浏览器打开链接
    } catch (e, stackTrace) {
      LogUtil.logError('打开浏览器失败: URL=$url', e, stackTrace);  // 增加具体错误信息，提高调试效率
    }
  }
}

// 版本实体类，存储版本号和更新日志
class VersionEntity {
  final String? latestVersion;  // 最新版本号
  final String? latestMsg;  // 最新版本的更新日志

  VersionEntity({this.latestVersion, this.latestMsg});
}
