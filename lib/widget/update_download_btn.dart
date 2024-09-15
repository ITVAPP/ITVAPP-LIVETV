import 'dart:io';

import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart'; 
import '../generated/l10n.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; 

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
                borderRadius: BorderRadius.circular(48),
                child: SizedBox(
                  height: 48,
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
                        S.of(context).downloading.replaceFirst('{progress}', (provider.progress * 100).toStringAsFixed(1)),   //下载中
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
          fixedSize: Size(btnWidth, 48),
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
              } catch (e, stackTrace) {
                LogUtil.logError('下载 APK 时发生错误', e, stackTrace);  // 异常日志记录
              }
            } else {
              try {
                Navigator.of(context).pop(true);
              } catch (e, stackTrace) {
                LogUtil.logError('关闭对话框时发生错误', e, stackTrace);  // 异常日志记录
              }
            }
          }, '点击下载按钮时发生错误');
        },
        child: Text(
          S.current.update,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
