import 'dart:io';
import 'package:itvapp_live_tv/widget/update_download_btn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart'; // 导入 Provider 包
import 'package:shared_preferences/shared_preferences.dart';  // 新增本地存储
import 'package:url_launcher/url_launcher.dart';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart'; // 导入 ThemeProvider
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
      LogUtil.v('保存最后提示日期成功');
    } catch (e, stackTrace) {
      LogUtil.logError('保存最后提示日期失败', e, stackTrace);
    }
  }

  // 获取最后一次弹出提示的日期
  static Future<String?> getLastPromptDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      LogUtil.v('获取最后提示日期成功');
      return prefs.getString('lastPromptDate');
    } catch (e, stackTrace) {
      LogUtil.logError('获取最后提示日期失败', e, stackTrace);
      return null;
    }
  }

  // 检查是否超过一天未提示
  static Future<bool> shouldShowPrompt() async {
    try {
      final lastPromptDate = await getLastPromptDate();
      if (lastPromptDate == null) return true; // 如果没有记录，说明从未提示过

      final lastDate = DateTime.parse(lastPromptDate);
      final currentDate = DateTime.now();

      // 检查是否超过1天
      return currentDate.difference(lastDate).inDays >= 1;
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace);
      return true; // 如果出现错误，默认返回 true
    }
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
          LogUtil.v('发现新版本: $latestVersion');
          return latestVersionEntity;
        } else {
          if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion);
          LogUtil.v('已是最新版: $version');
        }
      }
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace);
      return null;
    }
  }

  static Future<bool?> showUpdateDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        LogUtil.v('显示更新弹窗');
        
        // 获取屏幕的宽度和高度
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        // 判断屏幕是横屏还是竖屏
        final isPortrait = screenHeight > screenWidth;

        // 根据屏幕方向和屏幕宽度设置弹窗宽度为屏幕宽度的某个百分比
        final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;  // 竖屏时使用80%，横屏时使用60%

        return Center(
          child: Container(
            width: dialogWidth,  // 动态调整宽度
            decoration: BoxDecoration(
              color: const Color(0xFF2B2D30),
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)], 
                begin: Alignment.topCenter, 
                end: Alignment.bottomCenter,
              ),
            ),
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
                          LogUtil.v('用户关闭了更新弹窗');
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
                  apkUrl: '$downloadLink/${latestVersionEntity!.latestVersion}/easyTV-${latestVersionEntity!.latestVersion}.apk',
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }

  // 检查版本并提示
  static checkVersion(BuildContext context, [bool isShowLoading = true, bool isShowLatestToast = true, bool isManual = false]) async {
    try {
      // 如果是自动检查并且一天内已经提示过，则不再弹窗
      if (!isManual && !await shouldShowPrompt()) {
        LogUtil.v('一天内已提示过，无需再次弹窗');
        return;
      }

      // 手动或自动触发时检查版本
      final res = await checkRelease(isShowLoading, isShowLatestToast);
      if (res != null && context.mounted) {
        final isUpdate = await showUpdateDialog(context);
        if (isUpdate == true && !Platform.isAndroid) {
          launchBrowserUrl(releaseLink);
        }

        // 如果是自动检查，弹窗后保存提示时间
        if (!isManual) {
          await saveLastPromptDate();
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本时发生错误', e, stackTrace);
    }
  }

  static launchBrowserUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      LogUtil.v('成功打开浏览器: $url');
    } catch (e, stackTrace) {
      LogUtil.logError('打开浏览器失败', e, stackTrace);
    }
  }
}

class VersionEntity {
  final String? latestVersion;
  final String? latestMsg;

  VersionEntity({this.latestVersion, this.latestMsg});
}
