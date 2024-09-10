import 'dart:io';
import 'package:itvapp_live_tv/widget/update_download_btn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:shared_preferences/shared_preferences.dart';  // 新增本地存储
import 'package:url_launcher/url_launcher.dart';
import '../generated/l10n.dart';
import 'env_util.dart';
import 'http_util.dart';
import 'log_util.dart';

class CheckVersionUtil {
  static const version = '1.5.8';
  static final versionHost = EnvUtil.checkVersionHost();
  static final downloadLink = EnvUtil.sourceDownloadHost();
  static final releaseLink = EnvUtil.sourceReleaseHost();
  static final homeLink = EnvUtil.sourceHomeHost();
  static VersionEntity? latestVersionEntity;

  // 保存最后一次弹出提示的日期
  static Future<void> saveLastPromptDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastPromptDate', DateTime.now().toIso8601String());
    } catch (e) {
      LogUtil.e('保存最后提示日期失败: $e');
    }
  }

  // 获取最后一次弹出提示的日期
  static Future<String?> getLastPromptDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('lastPromptDate');
    } catch (e) {
      LogUtil.e('获取最后提示日期失败: $e');
      return null;
    }
  }

  // 检查是否超过一天未提示
  static Future<bool> shouldShowPrompt() async {
    final lastPromptDate = await getLastPromptDate();
    if (lastPromptDate == null) return true; // 如果没有记录，说明从未提示过

    final lastDate = DateTime.parse(lastPromptDate);
    final currentDate = DateTime.now();

    // 检查是否超过1天
    return currentDate.difference(lastDate).inDays >= 1;
  }

  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    if (latestVersionEntity != null) return latestVersionEntity;
    try {
      final res = await HttpUtil().getRequest(versionHost);
      if (res != null) {
        final latestVersion = res['tag_name'] as String?;
        final latestMsg = res['body'] as String?;
        if (latestVersion != null && latestVersion.compareTo(version) > 0) {
          latestVersionEntity = VersionEntity(latestVersion: latestVersion, latestMsg: latestMsg);
          return latestVersionEntity;
        } else {
          if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion);
          LogUtil.v('已是最新版::::::::');
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool?> showUpdateDialog(BuildContext context) async {
    bool isTV = EnvUtil.isTV();
    return showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: Container(
              width: isTV ? 600 : 300,
              decoration: BoxDecoration(
                  color: const Color(0xFF2B2D30),
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                      colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: Text(
                          '${S.current.findNewVersion}🚀',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          icon: const Icon(Icons.close),
                        ),
                      )
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    constraints: const BoxConstraints(minHeight: 200, minWidth: 300),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🎒 v${CheckVersionUtil.latestVersionEntity!.latestVersion}${S.current.updateContent}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('${CheckVersionUtil.latestVersionEntity!.latestMsg}'),
                        )
                      ],
                    ),
                  ),
                  UpdateDownloadBtn(
                      apkUrl: '$downloadLink/${latestVersionEntity!.latestVersion}/easyTV-${latestVersionEntity!.latestVersion}${isTV ? '-tv' : ''}.apk'),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        });
  }

  // 检查版本并提示
  static checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true]) async {
    // 检查是否需要提示
    if (!await shouldShowPrompt()) {
      return;  // 如果一天内已经提示过，则不再提示
    }

    final res = await checkRelease(isShowLoading, isShowLatestToast);
    if (res != null && context.mounted) {
      final isUpdate = await showUpdateDialog(context);
      if (isUpdate == true && !Platform.isAndroid) {
        launchBrowserUrl(releaseLink);
      }
    }

    // 保存最后一次提示日期
    await saveLastPromptDate();
  }

  static launchBrowserUrl(String url) async {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class VersionEntity {
  final String? latestVersion;
  final String? latestMsg;

  VersionEntity({this.latestVersion, this.latestMsg});
}
