import 'dart:io';
import 'package:itvapp_live_tv/widget/update_download_btn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import 'env_util.dart';
import 'http_util.dart';
import 'log_util.dart';

class CheckVersionUtil {
  static const version = '1.5.8';  // 当前应用版本号
  static final versionHost = EnvUtil.checkVersionHost();  // 版本检查的API地址
  static final downloadLink = EnvUtil.sourceDownloadHost();  // 应用下载链接的基础URL
  static final releaseLink = EnvUtil.sourceReleaseHost();  // 应用发布页面URL
  static final homeLink = EnvUtil.sourceHomeHost();  // 应用主页URL
  static VersionEntity? latestVersionEntity;  // 存储最新的版本信息

  // 保存最后一次弹出提示的日期
  static Future<void> saveLastPromptDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastPromptDate', DateTime.now().toIso8601String());
    } catch (e, stackTrace) {
      LogUtil.logError('保存最后提示日期失败', e, stackTrace);  // 错误处理
    }
  }

  // 获取最后一次弹出提示的日期
  static Future<String?> getLastPromptDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('lastPromptDate');  // 返回提示日期
    } catch (e, stackTrace) {
      LogUtil.logError('获取最后提示日期失败', e, stackTrace);  // 错误处理
      return null;  // 获取失败时返回 null
    }
  }

  // 检查是否超过一天未提示
  static Future<bool> shouldShowPrompt() async {
    try {
      final lastPromptDate = await getLastPromptDate();  // 获取最后一次提示日期
      if (lastPromptDate == null) return true;  // 如果没有记录，表示从未提示过，直接返回 true

      final lastDate = DateTime.parse(lastPromptDate);  // 解析最后提示的日期
      final currentDate = DateTime.now();  // 获取当前日期

      // 检查是否超过1天，若是则返回 true
      return currentDate.difference(lastDate).inDays >= 1;
    } catch (e, stackTrace) {
      LogUtil.logError('检查提示间隔失败', e, stackTrace);  // 错误处理
      return true;  // 发生错误时，默认返回 true，确保用户仍会收到提示
    }
  }

  // 检查最新版本，并返回版本信息
  static Future<VersionEntity?> checkRelease([bool isShowLoading = true, bool isShowLatestToast = true]) async {
    if (latestVersionEntity != null) return latestVersionEntity;  // 如果已有版本信息，则直接返回
    try {
      final res = await HttpUtil().getRequest(versionHost);  // 发送网络请求检查最新版本
      if (res != null) {
        final latestVersion = res['tag_name'] as String?;  // 获取最新版本号
        final latestMsg = res['body'] as String?;  // 获取最新版本的更新日志
        if (latestVersion != null && latestVersion.compareTo(version) > 0) {
          latestVersionEntity = VersionEntity(latestVersion: latestVersion, latestMsg: latestMsg);  // 存储新版本信息
          return latestVersionEntity;  // 返回最新版本信息
        } else {
          if (isShowLatestToast) EasyLoading.showToast(S.current.latestVersion);  // 如果是最新版本，显示提示
        }
      }
      return null;  // 如果没有新版本，返回 null
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查失败', e, stackTrace);  // 错误处理
      return null;  // 网络请求失败时返回 null
    }
  }

  // 显示版本更新的对话框
  static Future<bool?> showUpdateDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,  // 禁止点击对话框外关闭
      builder: (BuildContext context) {
        
        // 获取屏幕的宽度和高度
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        // 判断屏幕方向，决定对话框宽度比例
        final isPortrait = screenHeight > screenWidth;
        final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;  // 根据屏幕方向调整弹窗宽度
        final maxDialogHeight = screenHeight * 0.8;  // 设置对话框的最大高度为屏幕高度的80%

        return Center(
          child: Container(
            width: dialogWidth,  // 设置对话框宽度
            constraints: BoxConstraints(
              maxHeight: maxDialogHeight,  // 限制对话框最大高度
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2D30),
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)], 
                begin: Alignment.topCenter, 
                end: Alignment.bottomCenter,
              ),
            ),
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(), // TV端焦点遍历策略
              child: Column(
                mainAxisSize: MainAxisSize.min,  // 动态调整高度，适应内容
                children: [
                  Stack(
                    children: [
                      // 显示版本更新标题
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: Text(
                          '${S.current.findNewVersion}🚀',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                        ),
                      ),
                      // 关闭按钮，使用 Focus 控件包裹以支持 TV 焦点导航
                      Positioned(
                        right: 0,
                        child: Focus(
                          child: IconButton(
                            onPressed: () {
                              Navigator.of(context).pop(false);  // 点击关闭按钮，关闭对话框
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      )
                    ],
                  ),
                  // 内容区域，启用滚动，焦点可以在TV端上/下键切换
                  Flexible(  // 使用Flexible而不是Expanded，使内容区域根据实际内容调整
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(), // 让TV端可用遥控器导航内容
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,  // 自动调整高度以适应内容
                            children: [
                              Text(
                                '🎒 v${CheckVersionUtil.latestVersionEntity!.latestVersion}${S.current.updateContent}',  // 显示版本号
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                CheckVersionUtil.latestVersionEntity!.latestMsg ?? '',  // 显示版本更新日志
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 更新按钮，使用 Focus 控件包裹以支持 TV 焦点导航
                  FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(), // 确保TV端焦点可以通过遥控器切换
                    child: Focus(
                      child: UpdateDownloadBtn(
                        apkUrl: '$downloadLink/${latestVersionEntity!.latestVersion}/easyTV-${latestVersionEntity!.latestVersion}.apk',
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        );
      },
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
      LogUtil.logError('打开浏览器失败', e, stackTrace);  // 错误处理
    }
  }
}

// 版本实体类，存储版本号和更新日志
class VersionEntity {
  final String? latestVersion;  // 最新版本号
  final String? latestMsg;  // 最新版本的更新日志

  VersionEntity({this.latestVersion, this.latestMsg});
}
