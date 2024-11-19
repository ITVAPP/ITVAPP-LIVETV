import 'package:apk_installer/apk_installer.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

class DownloadProvider extends ChangeNotifier {
  static final DownloadProvider _instance = DownloadProvider._internal();
  factory DownloadProvider() => _instance;

  bool _isDownloading = false;
  double _progress = 0.0;
  String? _currentUrl;

  bool get isDownloading => _isDownloading;
  double get progress => _progress;

  DownloadProvider._internal();

  Future<void> downloadApk(String url) async {
    if (_isDownloading && url == _currentUrl) {
      LogUtil.v('已在下载中: $url');
      return;
    }

    try {
      await LogUtil.safeExecute(() async {
        _isDownloading = true;
        _currentUrl = url;
        _progress = 0.0;
        notifyListeners();
        LogUtil.v('开始下载 APK 文件: $url');

        final dir = await getTemporaryDirectory();
        final savePath = '${dir.path}/apk/${url.split('/').last}';
        LogUtil.v('APK 保存路径: $savePath');

        final code = await HttpUtil().downloadFile(
          url,
          savePath,
          progressCallback: (double currentProgress) {
            try {
              _progress = currentProgress;
              notifyListeners();
            } catch (e, stackTrace) {
              LogUtil.logError('更新下载进度时发生错误', e, stackTrace);
            }
          },
        );

        if (code == 200) {
          LogUtil.v('APK 文件下载完成，开始安装: $savePath');
          await ApkInstaller.installApk(filePath: savePath);
        } else {
          LogUtil.e('下载 APK 文件失败，错误码: $code');
          _isDownloading = false;
          notifyListeners();
        }
      }, '下载过程中发生错误');
    } catch (e, stackTrace) {
      LogUtil.logError('下载或安装 APK 时发生错误', e, stackTrace);
      _isDownloading = false;
      notifyListeners();
    } finally {
      if (code == 200) {
        _isDownloading = false;
        _currentUrl = null;
        notifyListeners();
      }
    }
  }
}
