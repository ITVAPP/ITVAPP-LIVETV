import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 播放器配置类，管理视频播放和通知相关的设置
class BetterPlayerConfig {
  // 背景图片Widget，用于播放器占位或错误界面
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover, // 覆盖整个区域
    gaplessPlayback: true, // 防止图片加载闪烁
    filterQuality: FilterQuality.medium, // 平衡图片质量与性能
  );
  
  // 默认通知图标路径
  static const String _defaultNotificationImage = 'logo.png';
  
  // 应用目录路径的缓存键，与main.dart一致
  static const String appDirectoryPathKey = 'app_directory_path';
  
  // 缓存Logo存储目录
  static Directory? _logoDirectory;
  
  // 防止重复下载Logo的集合
  static final Set<String> _downloadingLogos = {};
  
  // 缓存配置常量
  static const int _preCacheSize = 20 * 1024 * 1024; // 预缓存大小20MB
  static const int _maxCacheSize = 300 * 1024 * 1024; // 总缓存大小300MB
  static const int _maxCacheFileSize = 50 * 1024 * 1024; // 单文件缓存50MB
  
  // Logo文件大小限制2MB
  static const int _maxLogoFileSize = 2 * 1024 * 1024;
  
  /// 获取Logo存储目录，优先使用缓存路径
  static Future<Directory> _getLogoDirectory() async {
    if (_logoDirectory != null) return _logoDirectory!; // 返回缓存目录
    
    try {
      final appBasePath = SpUtil.getString(appDirectoryPathKey); // 读取缓存路径
      
      // 构建Logo目录路径
      final String logoPath;
      if (appBasePath == null || appBasePath.isEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        logoPath = '${appDir.path}/channel_logos';
      } else {
        logoPath = '$appBasePath/channel_logos';
      }
      
      final logoDir = Directory(logoPath);
      if (!await logoDir.exists()) {
        await logoDir.create(recursive: true); // 创建目录
      }
      
      _logoDirectory = logoDir; // 缓存目录
      return logoDir;
    } catch (e, stackTrace) {
      LogUtil.logError('创建Logo目录失败', e, stackTrace);
      final fallbackDir = await getApplicationDocumentsDirectory();
      LogUtil.i('使用备用目录: ${fallbackDir.path}');
      return fallbackDir; // 返回备用目录
    }
  }
  
  /// 从URL获取图片扩展名，默认为png
  static String _getImageExtension(String url) {
    try {
      // 获取URL最后部分
      final fileName = url.split('/').last;
      
      // 处理查询参数
      final cleanFileName = fileName.contains('?') ? fileName.split('?').first : fileName;
      
      // 提取扩展名
      final extensionMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(cleanFileName);
      if (extensionMatch != null) {
        return extensionMatch.group(1)!.toLowerCase();
      }
    } catch (e) {
      LogUtil.e('获取图片扩展名出错: $e');
    }
    
    return 'png'; // 默认扩展名
  }
  
  /// 生成安全的文件名（使用频道标题和原始图片扩展名）
  static String _generateSafeFileName(String channelTitle, String logoUrl) {
    // 清理频道标题，移除不安全字符
    final safeTitle = channelTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_'); // 替换空格为下划线
    
    // 获取原始扩展名
    final extension = _getImageExtension(logoUrl);
    
    // 避免空标题
    final fileName = safeTitle.isNotEmpty ? safeTitle : 'channel_${logoUrl.hashCode.abs()}';
    
    return '$fileName.$extension';
  }
  
  /// 根据频道标题和Logo URL生成唯一标识符
  static String _generateLogoIdentifier(String channelTitle, String logoUrl) {
    return '$channelTitle:${logoUrl.hashCode}';
  }
  
  /// 检查本地Logo文件是否存在，返回路径或null
  static Future<String?> _getLocalLogoPath(String channelTitle, String logoUrl) async {
    try {
      final fileName = _generateSafeFileName(channelTitle, logoUrl);
      final logoDir = await _getLogoDirectory();
      final localPath = '${logoDir.path}/$fileName';
      final file = File(localPath);
      
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 0) {
          LogUtil.i('找到本地Logo: $localPath');
          return localPath; // 返回有效文件路径
        } else {
          await file.delete(); // 删除无效文件
          LogUtil.e('Logo文件损坏，已删除: $localPath');
          return null;
        }
      }
      
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('检查本地Logo失败', e, stackTrace);
      return null;
    }
  }
  
  /// 下载Logo并保存到本地，防止重复下载
  static Future<void> _downloadLogoIfNeeded(String channelTitle, String logoUrl) async {
    if (!logoUrl.startsWith('http')) return; // 非网络资源跳过
    
    // 使用频道标题和URL组合生成唯一标识符
    final identifier = _generateLogoIdentifier(channelTitle, logoUrl);
    
    if (_downloadingLogos.contains(identifier)) {
      return; // 正在下载中，跳过
    }
    
    try {
      final localPath = await _getLocalLogoPath(channelTitle, logoUrl);
      if (localPath != null) return; // 本地已有，跳过
      
      _downloadingLogos.add(identifier); // 标记下载
      final fileName = _generateSafeFileName(channelTitle, logoUrl);
      final logoDir = await _getLogoDirectory();
      final savePath = '${logoDir.path}/$fileName';
      
      final httpUtil = HttpUtil();
      final result = await httpUtil.downloadFile(
        logoUrl,
        savePath,
        progressCallback: (progress) {
          // 进度回调的空实现，保留但提供完整的代码块
        },
        // 移除不支持的maxSize参数
      );
      
      if (result == HttpUtil.successStatusCode) {
        final file = File(savePath);
        if (await file.exists() && await file.length() == 0) {
          await file.delete(); // 删除无效文件
          LogUtil.e('Logo文件大小为0，已删除: $savePath');
        }
      } else {
        LogUtil.e('Logo下载失败，状态码: $result');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('下载Logo失败: $logoUrl', e, stackTrace);
    } finally {
      _downloadingLogos.remove(identifier); // 移除下载标记
    }
  }

  /// 检测视频URL格式，返回对应枚举值
  static BetterPlayerVideoFormat _detectVideoFormat(String url) {
    if (url.isEmpty) return BetterPlayerVideoFormat.other;
    
    final lowerCaseUrl = url.toLowerCase();
    
    if (lowerCaseUrl.contains('.mpd') || 
        lowerCaseUrl.contains('mime=application/dash+xml') ||
        lowerCaseUrl.contains('format=mpd')) {
      return BetterPlayerVideoFormat.dash; // DASH流
    } else if (lowerCaseUrl.contains('.ism') || 
               lowerCaseUrl.contains('/manifest') ||
               lowerCaseUrl.contains('format=ss')) {
      return BetterPlayerVideoFormat.ss; // SmoothStreaming流
    } else if (lowerCaseUrl.contains('.m3u8') || 
               lowerCaseUrl.contains('mime=application/x-mpegurl') ||
               lowerCaseUrl.contains('mime=application/vnd.apple.mpegurl') ||
               lowerCaseUrl.contains('format=m3u8')) {
      return BetterPlayerVideoFormat.hls; // HLS流
    } else {
      return BetterPlayerVideoFormat.other; // 其他格式
    }
  }

  /// 同步获取通知图标路径
  static String _getNotificationImagePath() {
    try {
      final appBasePath = SpUtil.getString(appDirectoryPathKey);
      if (appBasePath == null || appBasePath.isEmpty) {
        LogUtil.e('未找到缓存路径，使用默认图标路径');
        try {
          // 尝试记录SpUtil的状态，以便于诊断
          LogUtil.e('SpUtil.isInitialized=${SpUtil.isInitialized}');
          // 记录所有缓存的键，看是否能找到其他相关信息
          final allKeys = SpUtil.getKeys();
          LogUtil.e('SpUtil所有键: ${allKeys.join(', ')}');
        } catch (innerError) {
          LogUtil.e('获取SpUtil状态失败: $innerError');
        }
        return 'images/$_defaultNotificationImage';
      }
      
      final notificationPath = '$appBasePath/images/$_defaultNotificationImage';
      if (File(notificationPath).existsSync()) {
        LogUtil.i('使用通知图标绝对路径: $notificationPath');
        return notificationPath;
      }
      
      LogUtil.e('通知图标不存在，使用默认路径: $notificationPath');
      return 'images/$_defaultNotificationImage';
    } catch (e) {
      LogUtil.e('获取通知图标路径失败: $e');
      return 'images/$_defaultNotificationImage';
    }
  }

  /// 创建播放器数据源，配置视频流和通知
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
    String? channelTitle,
    String? channelLogo,
  }) {
    final defaultHeaders = HeadersConfig.generateHeaders(url: url); // 生成默认请求头
    final mergedHeaders = {...defaultHeaders, ...?headers}; // 合并请求头
    
    final title = channelTitle ?? S.current.appName; // 使用频道标题或应用名
    final isValidNetworkLogo = channelLogo != null && 
                              channelLogo.isNotEmpty && 
                              channelLogo.startsWith('http');
    
    if (isValidNetworkLogo && channelTitle != null && channelTitle.isNotEmpty) {
      _downloadLogoIfNeeded(channelTitle, channelLogo!); // 下载网络Logo并使用频道标题作为文件名
    }
    
    final imageUrl = isValidNetworkLogo ? channelLogo! : _getNotificationImagePath();
    final autoDetectedFormat = _detectVideoFormat(url); // 检测视频格式
    
    final videoFormat = autoDetectedFormat != BetterPlayerVideoFormat.other 
        ? autoDetectedFormat 
        : (isHls ? BetterPlayerVideoFormat.hls : BetterPlayerVideoFormat.other);
    
    final liveStream = isHls || videoFormat == BetterPlayerVideoFormat.hls; // 判断是否直播
    
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      videoFormat: videoFormat,
      liveStream: liveStream,
      useAsmsTracks: liveStream, // 直播启用ASMS轨道
      useAsmsAudioTracks: liveStream,
      useAsmsSubtitles: false, // 禁用字幕
      headers: mergedHeaders.isNotEmpty ? mergedHeaders : null,
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: true,
        title: title,
        author: S.current.appName,
        imageUrl: imageUrl,
        notificationChannelName: Config.packagename,
        activityName: "${Config.packagename}.MainActivity",
      ),
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000,
        maxBufferMs: 20000,
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !liveStream, // 非直播启用缓存
        preCacheSize: _preCacheSize,
        maxCacheSize: _maxCacheSize,
        maxCacheFileSize: _maxCacheFileSize,
      ),
    );
  }

  /// 创建播放器配置，设置播放行为和界面
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain,
      autoPlay: false,
      looping: isHls, // 直播循环播放
      allowedScreenSleep: false,
      autoDispose: false,
      expandToFill: true,
      handleLifecycle: true,
      errorBuilder: (_, __) => _backgroundImage, // 错误界面显示背景
      placeholder: _backgroundImage, // 占位图片
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // 隐藏控制栏
      ),
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      eventListener: eventListener, // 绑定事件监听
    );
  }
}
