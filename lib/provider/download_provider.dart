import 'package:flutter/material.dart';
import 'package:apk_installer/apk_installer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 下载管理类，负责 APK 文件的下载和安装操作
class DownloadProvider extends ChangeNotifier {
  // 单例模式，确保全局只有一个 DownloadProvider 实例
  static final DownloadProvider _instance = DownloadProvider._internal();
  factory DownloadProvider() => _instance;

  // 私有属性，用于跟踪下载状态和进度
  bool _isDownloading = false; // 标识当前是否正在下载
  double _progress = 0.0; // 下载进度，0.0 到 1.0
  String? _currentUrl; // 当前下载的文件 URL

  // 获取当前下载状态
  bool get isDownloading => _isDownloading;

  // 获取当前下载进度
  double get progress => _progress;

  // 私有构造函数，初始化单例
  DownloadProvider._internal();

  /// 下载并安装 APK 文件
  /// [url] 指定要下载的 APK 文件的 URL
  Future<void> downloadApk(String url) async {
    // 如果已经在下载相同的 URL，则直接返回避免重复下载
    if (_isDownloading && url == _currentUrl) {
      LogUtil.v('已在下载中: $url');
      return;
    }

    try {
      // 初始化下载状态
      _isDownloading = true;
      _currentUrl = url;
      _progress = 0.0;
      notifyListeners(); // 通知监听者下载状态和进度已更新
      LogUtil.v('开始下载 APK 文件: $url');

      // 获取临时目录路径，并生成 APK 文件的保存路径
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/apk/${url.split('/').last}';
      LogUtil.v('APK 保存路径: $savePath');

      // 开始下载文件，并设置下载进度回调
      final downloadCode = await HttpUtil().downloadFile(
        url,
        savePath,
        progressCallback: (double currentProgress) {
          try {
            _progress = currentProgress; // 更新下载进度
            notifyListeners(); // 通知监听者进度已更新
          } catch (e, stackTrace) {
            LogUtil.logError('更新下载进度时发生错误', e, stackTrace);
          }
        },
      );

      // 检查下载是否成功
      if (downloadCode == 200) {
        LogUtil.v('APK 文件下载完成，开始安装: $savePath');
        // 下载成功后开始安装 APK 文件
        await ApkInstaller.installApk(filePath: savePath);
      } else {
        LogUtil.e('下载 APK 文件失败，错误码: $downloadCode');
        _isDownloading = false; // 设置下载状态为未下载
        notifyListeners(); // 通知监听者状态更新
      }
    } catch (e, stackTrace) {
      // 捕获下载或安装过程中可能发生的错误并记录日志
      LogUtil.logError('下载或安装 APK 时发生错误', e, stackTrace);
      _isDownloading = false; // 设置下载状态为未下载
      notifyListeners(); // 通知监听者状态更新
    } finally {
      // 重置下载状态，释放当前 URL
      _isDownloading = false;
      _currentUrl = null;
      notifyListeners(); // 通知监听者状态更新
    }
  }
}
