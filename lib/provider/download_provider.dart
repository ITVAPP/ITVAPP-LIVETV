import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:apk_installer/apk_installer.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

// 下载管理类，负责APK下载和安装
class DownloadProvider extends ChangeNotifier {
  // 单例实例
  static final DownloadProvider _instance = DownloadProvider._internal();
  factory DownloadProvider() => _instance;

  // 当前是否正在下载
  bool _isDownloading = false;
  // 下载进度，0.0到1.0
  double _progress = 0.0;
  // 当前下载的文件URL
  String? _currentUrl;
  // 最后一次进度更新时间
  DateTime? _lastProgressUpdate;
  // 进度更新最小间隔，100毫秒
  static const Duration _progressUpdateInterval = Duration(milliseconds: 100);
  // 待更新的进度值
  double _pendingProgress = 0.0;

  // 获取下载状态
  bool get isDownloading => _isDownloading;
  // 获取下载进度
  double get progress => _progress;

  // 私有构造函数
  DownloadProvider._internal();

  // 更新下载状态并通知监听者
  void _updateState({required bool isDownloading, required double progress, String? currentUrl}) {
    _isDownloading = isDownloading;
    _progress = progress;
    _currentUrl = currentUrl;
    notifyListeners(); // 通知状态更新
  }

  // 节流更新下载进度
  void _throttledProgressUpdate(double progress, {bool forceUpdate = false}) {
    _pendingProgress = progress;
    final now = DateTime.now();
    final shouldUpdate = forceUpdate ||
        _lastProgressUpdate == null ||
        now.difference(_lastProgressUpdate!) >= _progressUpdateInterval;

    if (shouldUpdate) {
      _lastProgressUpdate = now;
      _progress = _pendingProgress;
      notifyListeners(); // 更新进度
    }
  }

  // 下载并安装APK文件
  Future<void> downloadApk(String url) async {
    // 避免重复下载相同URL
    if (_isDownloading && url == _currentUrl) {
      LogUtil.v('正在下载: $url');
      return;
    }

    try {
      // 初始化下载状态
      _updateState(isDownloading: true, progress: 0.0, currentUrl: url);
      _lastProgressUpdate = null;

      LogUtil.v('开始下载APK: $url');

      // 获取临时目录并创建APK子目录
      final dir = await getTemporaryDirectory();
      final apkDir = Directory('${dir.path}/apk');
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }

      // 解析文件名，失败时使用默认名
      final fileName = p.basename(url).isNotEmpty ? p.basename(url) : 'downloaded_app.apk';
      final savePath = '${apkDir.path}/$fileName';

      LogUtil.v('APK保存路径: $savePath');

      // 下载APK文件，设置进度回调和5分钟超时
      final downloadCode = await HttpUtil().downloadFile(
        url,
        savePath,
        progressCallback: (double currentProgress) {
          try {
            // 节流更新进度，完成时强制更新
            _throttledProgressUpdate(currentProgress, forceUpdate: currentProgress >= 1.0);
          } catch (e, stackTrace) {
            LogUtil.logError('更新APK下载进度异常', e, stackTrace);
          }
        },
      ).timeout(const Duration(minutes: 5), onTimeout: () {
        throw Exception('APK下载超时');
      });

      // 确保最终进度为100%
      _throttledProgressUpdate(1.0, forceUpdate: true);

      // 检查下载结果
      if (downloadCode == 200) {
        LogUtil.v('APK下载完成，开始安装: $savePath');

        // 安装APK
        try {
          await ApkInstaller.installApk(filePath: savePath);

          // 清理临时文件
          final file = File(savePath);
          if (await file.exists()) {
            await file.delete();
            LogUtil.v('临时文件已清理: $savePath');
          }
        } catch (e, stackTrace) {
          LogUtil.logError('APK安装异常', e, stackTrace);
          throw Exception('APK安装失败: $e');
        }
      } else {
        LogUtil.e('APK下载失败，错误码: $downloadCode');
        _updateState(isDownloading: false, progress: 0.0, currentUrl: null);
        throw Exception('APK下载失败，错误码: $downloadCode');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('APK下载流程异常', e, stackTrace);
      throw e;
    } finally {
      // 重置下载状态
      _updateState(isDownloading: false, progress: 0.0, currentUrl: null);
      _lastProgressUpdate = null;
    }
  }
}
