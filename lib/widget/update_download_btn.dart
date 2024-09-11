import 'dart:io';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart'; // 导入 ThemeProvider
import '../generated/l10n.dart';

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
          LogUtil.safeExecute(() async {
            if (Platform.isAndroid) {
              LogUtil.v('开始下载APK：${widget.apkUrl}');
              await context.read<DownloadProvider>().downloadApk(widget.apkUrl);
            } else {
              LogUtil.v('非Android设备，跳转到更新页面');
              Navigator.of(context).pop(true);
            }
          }, '下载APK或跳转更新页面过程中发生错误');
        },
        child: Text(
          S.current.update,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
