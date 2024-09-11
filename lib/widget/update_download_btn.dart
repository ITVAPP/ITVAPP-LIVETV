import 'dart:io';

import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';  // 导入 ThemeProvider
import '../generated/l10n.dart';
import 'package:itvapp_live_tv/util/log_util.dart';  // 导入日志工具

class UpdateDownloadBtn extends StatefulWidget {
  final String apkUrl;

  const UpdateDownloadBtn({super.key, this.apkUrl = ''});

  @override
  State<UpdateDownloadBtn> createState() => _UpdateDownloadBtnState();
}

class _UpdateDownloadBtnState extends State<UpdateDownloadBtn> {
  bool _isFocusDownload = true;

  @override
  Widget build(BuildContext context) {
    // 通过 Provider 获取 isTV 的状态
    bool isTV = context.watch<ThemeProvider>().isTV;
    double btnWidth = isTV ? 400 : 260;

    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        return provider.isDownloading
            ? ClipRRect(
                borderRadius: BorderRadius.circular(44),
                child: SizedBox(
                  height: 44,
                  width: btnWidth,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: LinearProgressIndicator(
                          value: provider.progress,
                          backgroundColor: Colors.redAccent.withOpacity(0.2),
                          color: Colors.redAccent,
                        ),
                      ),
                      Text(
                        '下载中...${(provider.progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      )
                    ],
                  ),
                ),
              )
            : child!;
      },
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          fixedSize: Size(btnWidth, 44),
          backgroundColor: _isFocusDownload ? Colors.redAccent : Colors.redAccent.withOpacity(0.3),
          elevation: _isFocusDownload ? 10 : 0,
          overlayColor: Colors.transparent,
        ),
        autofocus: true,
        onFocusChange: (bool isFocus) {
          setState(() {
            _isFocusDownload = isFocus;
          });
        },
        onPressed: () {
          LogUtil.safeExecute(() {
            if (Platform.isAndroid) {
              try {
                context.read<DownloadProvider>().downloadApk(widget.apkUrl);
                LogUtil.i('开始下载 APK: ${widget.apkUrl}');
              } catch (e, stackTrace) {
                LogUtil.logError('下载 APK 时发生错误', e, stackTrace);
              }
            } else {
              try {
                Navigator.of(context).pop(true);
                LogUtil.i('非 Android 设备，返回上一级');
              } catch (e, stackTrace) {
                LogUtil.logError('非 Android 设备处理返回时出错', e, stackTrace);
              }
            }
          }, '执行下载操作时发生错误');
        },
        child: Text(
          S.current.update,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
