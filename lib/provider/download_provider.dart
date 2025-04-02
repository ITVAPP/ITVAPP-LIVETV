import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:apk_installer/apk_installer.dart';
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

  /// 更新下载状态并通知监听者
  /// [isDownloading] 下载状态
  /// [progress] 下载进度
  /// [currentUrl] 当前下载的 URL，可为空
  void _updateState({required bool isDownloading, required double progress, String? currentUrl}) {
    _isDownloading = isDownloading;
    _progress = progress;
    _currentUrl = currentUrl;
    notifyListeners(); // 统一通知监听者状态更新
  }

  /// 下载并安装 APK 文件
  /// [url] 指定要下载的 APK 文件的 URL
  /// [onComplete] 下载成功并开始安装时的回调
  /// [onFailed] 下载失败时的回调
  Future<void> downloadApk(String url, {VoidCallback? onComplete, Function(String)? onFailed}) async {
    if (_isDownloading && url == _currentUrl) {
      LogUtil.v('已在下载中: $url');
      return;
    }

    try {
      _updateState(isDownloading: true, progress: 0.0, currentUrl: url);
      LogUtil.v('开始下载 APK 文件: $url');

      final dir = await getTemporaryDirectory();
      final apkDir = Directory('${dir.path}/apk');
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }
      final fileName = p.basename(url).isNotEmpty ? p.basename(url) : 'downloaded_app.apk';
      final savePath = '${apkDir.path}/$fileName';
      LogUtil.v('APK 保存路径: $savePath');

      final downloadCode = await HttpUtil().downloadFile(
        url,
        savePath,
        progressCallback: (double currentProgress) {
          try {
            _updateState(isDownloading: true, progress: currentProgress, currentUrl: url);
          } catch (e, stackTrace) {
            LogUtil.logError('更新下载进度时发生错误', e, stackTrace);
          }
        },
      ).timeout(const Duration(minutes: 5), onTimeout: () {
        throw Exception('下载超时');
      });

      if (downloadCode == 200) {
        LogUtil.v('APK 文件下载完成，开始安装: $savePath');
        try {
          await ApkInstaller.installApk(filePath: savePath);
          final file = File(savePath);
          if (await file.exists()) {
            await file.delete();
            LogUtil.v('临时文件已清理: $savePath');
          }
          onComplete?.call(); // 下载成功并开始安装后调用回调
        } catch (e, stackTrace) {
          LogUtil.logError('安装 APK 时发生错误', e, stackTrace);
          onFailed?.call('安装失败: $e'); // 安装失败时调用失败回调
        }
      } else {
        LogUtil.e('下载 APK 文件失败，错误码: $downloadCode');
        onFailed?.call('下载失败，错误码: $downloadCode'); // 下载失败时调用失败回调
      }
    } catch (e, stackTrace) {
      LogUtil.logError('下载 APK 时发生错误', e, stackTrace);
      onFailed?.call('下载错误: $e'); // 捕获异常并调用失败回调
    } finally {
      _updateState(isDownloading: false, progress: 0.0, currentUrl: null);
    }
  }
}
