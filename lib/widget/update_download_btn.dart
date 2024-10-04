import 'dart:io';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart'; 
import '../generated/l10n.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; 

class UpdateDownloadBtn extends StatefulWidget {
  // APK 下载链接
  final String apkUrl;

  const UpdateDownloadBtn({super.key, this.apkUrl = ''});

  @override
  State<UpdateDownloadBtn> createState() => _UpdateDownloadBtnState();
}

class _UpdateDownloadBtnState extends State<UpdateDownloadBtn> {
  // 控制按钮的焦点状态
  bool _isFocusDownload = true;

  @override
  Widget build(BuildContext context) {
    // 判断当前屏幕方向是否为横屏
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 根据屏幕方向设置按钮宽度
    double btnWidth = isLandscape ? 380 : 220;

    return Consumer<DownloadProvider>(
      // 监听下载状态，当下载进行时显示进度条，否则显示普通按钮
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        return provider.isDownloading
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16), // 圆角按钮样式
                child: SizedBox(
                  height: 48,
                  width: btnWidth, // 按钮宽度
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    alignment: Alignment.center,
                    children: [
                      // 下载进度条
                      Positioned.fill(
                        child: LinearProgressIndicator(
                          value: provider.progress, // 进度条的进度
                          backgroundColor: Color(0xFFEB144C).withOpacity(0.2), // 进度条背景颜色
                          color: Color(0xFFEB144C), // 进度条前景颜色
                        ),
                      ),
                      // 下载进度的文字显示
                      Text(
                        '${S.of(context).downloading} ${(provider.progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white, // 白色文字
                          fontWeight: FontWeight.bold,  // 文字加粗
                          fontSize: 16,  // 文字大小
                          ),
                      )
                    ],
                  ),
                ),
              )
            : child!;
      },
      // 普通按钮的样式和功能
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          fixedSize: Size(btnWidth, 48), // 固定按钮尺寸
          backgroundColor: _isFocusDownload ? Color(0xFFEB144C) : Color(0xFFE0E0E0),  // 根据焦点状态修改背景颜色
          elevation: _isFocusDownload ? 10 : 0, // 焦点状态下有阴影效果
          foregroundColor: Colors.white,  // 设置点击时水波纹的颜色
          shadowColor: _isFocusDownload ? Color(0xFFEB144C) : Color(0xFFE0E0E0),  // 阴影颜色与按钮背景匹配
        ),
        autofocus: true, // 自动获取焦点
        onFocusChange: (bool isFocus) {
          setState(() {
            _isFocusDownload = isFocus; // 更新按钮焦点状态
          });
        },
        // 按钮点击事件处理逻辑
        onPressed: () {
          LogUtil.safeExecute(() {
            if (Platform.isAndroid) { // 如果平台是 Android
              try {
                context.read<DownloadProvider>().downloadApk(widget.apkUrl); // 执行 APK 下载
              } catch (e, stackTrace) {
                LogUtil.logError('下载时发生错误', e, stackTrace);  // 记录下载时的错误
              }
            } else { // 如果不是 Android
              try {
                Navigator.of(context).pop(true); // 关闭对话框
              } catch (e, stackTrace) {
                LogUtil.logError('关闭对话框时发生错误', e, stackTrace);  // 记录关闭对话框时的错误
              }
            }
          }, '点击下载按钮时发生错误');
        },
        // 按钮上的文字样式
        child: Text(
          S.of(context).update, // 按钮显示文字
          style: const TextStyle(
            color: Colors.white, // 白色文字
            fontWeight: FontWeight.bold,  // 文字加粗
            fontSize: 18,  // 文字大小
          ),
        ),
      ),
    );
  }
}
