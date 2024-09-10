import 'dart:io';

import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../generated/l10n.dart';

class UpdateDownloadBtn extends StatefulWidget {
  final String apkUrl;

  const UpdateDownloadBtn({super.key, this.apkUrl = ''});

  @override
  State<UpdateDownloadBtn> createState() => _UpdateDownloadBtnState();
}

class _UpdateDownloadBtnState extends State<UpdateDownloadBtn> {
  bool _isFocusDownload = true;
  double btnWidth = 260; // 默认按钮宽度

  @override
  void initState() {
    super.initState();
    // 异步获取是否为TV设备，决定按钮的宽度
    _checkIsTV();
  }

  // 异步检查设备是否为TV，并设置按钮宽度
  Future<void> _checkIsTV() async {
    bool isTV = await EnvUtil.isTV(); // 异步调用获取是否为TV
    setState(() {
      btnWidth = isTV ? 400 : 260; // 根据设备类型设置按钮宽度
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        return provider.isDownloading
            ? ClipRRect(
                borderRadius: BorderRadius.circular(44),
                child: SizedBox(
                  height: 44,
                  width: btnWidth, // 按照设备类型设置的宽度
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
            fixedSize: Size(btnWidth, 44), // 按照设备类型设置的宽度
            backgroundColor: _isFocusDownload ? Colors.redAccent : Colors.redAccent.withOpacity(0.3),
            elevation: _isFocusDownload ? 10 : 0,
            overlayColor: Colors.transparent),
        autofocus: true,
        onFocusChange: (bool isFocus) {
          setState(() {
            _isFocusDownload = isFocus;
          });
        },
        onPressed: () {
          if (Platform.isAndroid) {
            context.read<DownloadProvider>().downloadApk(widget.apkUrl);
          } else {
            Navigator.of(context).pop(true);
          }
        },
        child: Text(
          S.current.update,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
