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
  
  // 进度更新节流相关变量
  DateTime? _lastProgressUpdate; // 最后一次进度更新时间
  static const Duration _progressUpdateInterval = Duration(milliseconds: 100); // 进度更新最小间隔
  double _pendingProgress = 0.0; // 待更新的进度值
  
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
  
  /// 节流进度更新，避免过于频繁的 UI 更新
  /// [progress] 当前下载进度
  /// [forceUpdate] 是否强制更新（用于完成时确保 100% 被显示）
  void _throttledProgressUpdate(double progress, {bool forceUpdate = false}) {
    _pendingProgress = progress;
    
    final now = DateTime.now();
    final shouldUpdate = forceUpdate || 
        _lastProgressUpdate == null || 
        now.difference(_lastProgressUpdate!) >= _progressUpdateInterval;
    
    if (shouldUpdate) {
      _lastProgressUpdate = now;
      _progress = _pendingProgress;
      notifyListeners();
    }
  }
  
  /// 下载并安装 APK 文件
  /// [url] 指定要下载的 APK 文件的 URL
  /// 返回 Future<void>，表示下载和安装操作的完成
  Future<void> downloadApk(String url) async {
    // 如果已经在下载相同的 URL，则直接返回避免重复下载
    if (_isDownloading && url == _currentUrl) {
      LogUtil.v('已在下载中: $url');
      return;
    }
    
    try {
      // 初始化下载状态
      _updateState(isDownloading: true, progress: 0.0, currentUrl: url);
      _lastProgressUpdate = null; // 重置进度更新时间
      
      LogUtil.v('开始下载 APK 文件: $url');
      
      // 获取临时目录路径，并生成 APK 文件的保存路径
      final dir = await getTemporaryDirectory();
      final apkDir = Directory('${dir.path}/apk');
      
      // 检查并创建 apk 子目录
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }
      
      // 使用 path 包解析文件名，若无法解析则使用默认文件名
      final fileName = p.basename(url).isNotEmpty ? p.basename(url) : 'downloaded_app.apk';
      final savePath = '${apkDir.path}/$fileName';
      
      LogUtil.v('APK 保存路径: $savePath');
      
      // 开始下载文件，并设置下载进度回调，添加超时机制
      final downloadCode = await HttpUtil().downloadFile(
        url,
        savePath,
        progressCallback: (double currentProgress) {
          try {
            // 使用节流更新进度，完成时强制更新
            _throttledProgressUpdate(currentProgress, forceUpdate: currentProgress >= 1.0);
          } catch (e, stackTrace) {
            LogUtil.logError('更新下载进度时发生错误', e, stackTrace);
          }
        },
      ).timeout(const Duration(minutes: 5), onTimeout: () {
        throw Exception('下载超时');
      });
      
      // 确保最终进度为 100%
      _throttledProgressUpdate(1.0, forceUpdate: true);
      
      // 检查下载是否成功
      if (downloadCode == 200) {
        LogUtil.v('APK 文件下载完成，开始安装: $savePath');
        
        // 下载成功后开始安装 APK 文件
        try {
          await ApkInstaller.installApk(filePath: savePath);
          
          // 安装完成后清理临时文件
          final file = File(savePath);
          if (await file.exists()) {
            await file.delete();
            LogUtil.v('临时文件已清理: $savePath');
          }
        } catch (e, stackTrace) {
          LogUtil.logError('安装 APK 时发生错误', e, stackTrace);
          throw Exception('安装失败: $e'); // 安装失败也视为下载流程失败
        }
      } else {
        LogUtil.e('下载 APK 文件失败，错误码: $downloadCode');
        _updateState(isDownloading: false, progress: 0.0, currentUrl: null);
        throw Exception('下载失败，错误码: $downloadCode');
      }
    } catch (e, stackTrace) {
      // 捕获下载过程中可能发生的错误并记录日志
      LogUtil.logError('下载 APK 时发生错误', e, stackTrace);
      throw e; // 将异常抛出给调用者处理
    } finally {
      // 重置下载状态，释放当前 URL
      _updateState(isDownloading: false, progress: 0.0, currentUrl: null);
      _lastProgressUpdate = null; // 清理进度更新时间
    }
  }
}
