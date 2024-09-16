import 'dart:io';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';  // 导入 ThemeProvider
import '../generated/l10n.dart';
import 'package:itvapp_live_tv/util/log_util.dart';  // 导入 LogUtil 用于日志记录

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
    // 判断当前屏幕方向是否为横屏
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 在横屏时使用TV端的按钮宽度
    double btnWidth = isLandscape ? 400 : 260;

    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        return provider.isDownloading
            ? ClipRRect(
                borderRadius: BorderRadius.circular(38),
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
                        '${S.of(context).downloading}...${(provider.progress * 100).toStringAsFixed(1)}%',
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
          fixedSize: Size(btnWidth, 48),  // 横屏时的按钮宽度
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
