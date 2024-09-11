import 'package:apk_installer/apk_installer.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../util/http_util.dart';

class DownloadProvider extends ChangeNotifier {
  bool _isDownloading = false;
  double _progress = 0.0;

  bool get isDownloading => _isDownloading;
  double get progress => _progress;

  Future<void> downloadApk(String url) async {
    _isDownloading = true;
    notifyListeners();

    LogUtil.safeExecute(() async {
      final savePath = '${(await getTemporaryDirectory()).path}/apk/${url.split('/').last}';
      LogUtil.v('download apk :::: $url');
      LogUtil.v('apk save path:::: $savePath');

      final code = await HttpUtil().downloadFile(url, savePath, progressCallback: (double currentProgress) {
        _progress = currentProgress;
        notifyListeners();
      });

      if (code == 200) {
        await ApkInstaller.installApk(filePath: savePath);
      } else {
        LogUtil.logError('APK下载失败，状态码: $code');
        _isDownloading = false;
        notifyListeners();
      }
    }, 'APK下载过程中发生错误');
  }
}
