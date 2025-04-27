import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class BetterPlayerConfig {
  // 定义常量背景图片Widget
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover,
    gaplessPlayback: true,  // 防止图片加载时闪烁
    filterQuality: FilterQuality.medium,  // 优化图片质量和性能的平衡
  );
  
  // 定义默认的通知图标路径
  static const String _defaultNotificationImage = 'assets/images/logo.png';
  
  // Logo文件夹路径缓存
  static Directory? _logoDirectory;
  
  // 用于防止重复下载同一Logo的集合
  static final Set<String> _downloadingLogos = {};
  
  // 缓存相关常量配置，便于统一管理和修改
  static const int _preCacheSize = 20 * 1024 * 1024; // 预缓存大小（20MB）
  static const int _maxCacheSize = 300 * 1024 * 1024; // 缓存总大小限制（300MB）
  static const int _maxCacheFileSize = 50 * 1024 * 1024; // 单个缓存文件大小限制（50MB）
  
  /// 获取Logo存储目录
  static Future<Directory> _getLogoDirectory() async {
    if (_logoDirectory != null) return _logoDirectory!;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logoDir = Directory('${appDir.path}/channel_logos');
      
      // 确保目录存在
      if (!await logoDir.exists()) {
        await logoDir.create(recursive: true);
      }
      
      _logoDirectory = logoDir;
      return logoDir;
    } catch (e, stackTrace) {
      LogUtil.logError('创建Logo目录失败', e, stackTrace);
      // 如果创建失败，返回应用文档目录
      return await getApplicationDocumentsDirectory();
    }
  }
  
  /// 从URL提取文件名，处理带参数的情况
  static String _extractFileName(String url) {
    // 先提取路径最后一部分作为文件名
    String fileName = url.split('/').last;
    
    // 如果文件名含有参数（包含?号），只保留?号前面的部分
    if (fileName.contains('?')) {
      fileName = fileName.split('?').first;
    }
    
    // 如果提取后文件名为空，使用URL哈希值作为文件名
    if (fileName.isEmpty) {
      final hash = url.hashCode.abs().toString();
      return 'logo_$hash.png'; // 使用默认.png扩展名
    }
    
    // 确保文件名有合适的扩展名
    if (!_hasImageExtension(fileName)) {
      return '$fileName.png';
    }
    
    return fileName;
  }
  
  /// 检查文件名是否包含常见图像扩展名
  static bool _hasImageExtension(String fileName) {
    final imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];
    return imageExtensions.any((ext) => fileName.toLowerCase().endsWith(ext));
  }
  
  /// 检查本地是否有保存的logo
  /// 返回本地文件路径，如果不存在则返回null
  static Future<String?> _getLocalLogoPath(String channelLogo) async {
    try {
      // 提取文件名 (处理带参数的URL)
      final fileName = _extractFileName(channelLogo);
      
      final logoDir = await _getLogoDirectory();
      final localPath = '${logoDir.path}/$fileName';
      final file = File(localPath);
      
      // 检查文件是否存在
      if (await file.exists()) {
        LogUtil.i('找到本地缓存的Logo: $localPath');
        return localPath;
      }
      
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('检查本地Logo失败', e, stackTrace);
      return null;
    }
  }
  
  /// 下载Logo并保存到本地
  static Future<void> _downloadLogoIfNeeded(String channelLogo) async {
    // 非网络资源，无需下载
    if (!channelLogo.startsWith('http')) return;
    
    // 添加防重复下载机制
    if (_downloadingLogos.contains(channelLogo)) {
      LogUtil.i('Logo正在下载中，跳过: $channelLogo');
      return;
    }
    
    try {
      // 检查本地是否已有该Logo
      final localPath = await _getLocalLogoPath(channelLogo);
      if (localPath != null) return; // 已经存在，无需下载
      
      // 标记为正在下载
      _downloadingLogos.add(channelLogo);
      
      // 提取文件名，处理带参数的情况
      final fileName = _extractFileName(channelLogo);
      
      final logoDir = await _getLogoDirectory();
      final savePath = '${logoDir.path}/$fileName';
      
      // 创建HttpUtil实例进行下载
      final httpUtil = HttpUtil();
      final result = await httpUtil.downloadFile(
        channelLogo,
        savePath,
        progressCallback: (progress) {
          if (progress == 1.0) {
            LogUtil.i('Logo下载完成: $savePath');
          }
        },
      );
      
      // 检查下载结果
      if (result == HttpUtil.successStatusCode) {
        LogUtil.i('Logo已下载并保存: $savePath');
      } else {
        LogUtil.e('Logo下载失败，状态码: $result');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('下载Logo失败: $channelLogo', e, stackTrace);
    } finally {
      // 无论成功失败，都移除下载标记
      _downloadingLogos.remove(channelLogo);
    }
  }

  /// 创建播放器数据源配置
  /// - [url]: 视频播放地址，必须是有效的URL
  /// - [isHls]: 是否为 HLS 格式（直播流）
  /// - [headers]: 可选的HTTP请求头，用于认证或特殊请求
  /// - [channelTitle]: 频道标题，用于通知栏显示
  /// - [channelLogo]: 频道LOGO路径，支持网络URL或本地资源路径
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
    String? channelTitle,
    String? channelLogo,
  }) {
    // 使用 HeadersConfig 生成默认 headers
    final defaultHeaders = HeadersConfig.generateHeaders(url: url);
    // 合并 defaultHeaders 和传入的 headers
    final mergedHeaders = {...defaultHeaders, ...?headers};
    
    // 先异步检查和下载Logo，但不阻塞数据源创建
    if (channelLogo != null && channelLogo.isNotEmpty) {
      _downloadLogoIfNeeded(channelLogo);
    }
    
    // 确定要使用的imageUrl
    final imageUrl = (channelLogo != null && channelLogo.isNotEmpty) 
        ? channelLogo 
        : _defaultNotificationImage;
    
    // 创建数据源配置
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      videoFormat: isHls ? BetterPlayerVideoFormat.hls : BetterPlayerVideoFormat.other, 
      liveStream: isHls, // 根据 isHls 参数设置是否为直播流
      useAsmsTracks: isHls, // 仅直播流启用 ASMS 音视频轨道
      useAsmsAudioTracks: isHls, // 同上
      useAsmsSubtitles: false, // 禁用字幕以降低播放开销
      headers: mergedHeaders.isNotEmpty ? mergedHeaders : null, // 仅当有头部信息时添加
      // 配置系统通知栏行为
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: true, // 启用通知栏显示
        title: channelTitle ?? S.current.appName, // 频道标题或默认应用名
        author: S.current.appName, // 设置通知作者为应用名
        imageUrl: imageUrl, // 使用频道LOGO或默认图标
        notificationChannelName: Config.packagename, // Android通知渠道名称
        activityName: "itvapp_live_tv.MainActivity", // 指定通知跳转Activity
      ),
      // 缓冲配置
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000, // 5 秒
        maxBufferMs: 20000, // 20 秒
        bufferForPlaybackMs: 2500, // 2.5秒
        bufferForPlaybackAfterRebufferMs: 5000, // 5秒
      ),
      // 缓存配置
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls, // 非 HLS 启用缓存（直播流不适合缓存）
        preCacheSize: _preCacheSize,
        maxCacheSize: _maxCacheSize,
        maxCacheFileSize: _maxCacheFileSize,
      ),
    );
  }

  /// 创建播放器基本配置
  /// - [isHls]: 是否为HLS直播流，会影响循环播放等设置
  /// - [eventListener]: 事件监听回调函数，用于处理播放器状态变化
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 播放器内容适应模式（保持比例缩放）
      autoPlay: false, // 自动播放
      looping: isHls, // 是HLS时循环播放
      allowedScreenSleep: false, // 屏幕休眠
      autoDispose: false, // 自动释放资源
      expandToFill: true, // 填充剩余空间
      handleLifecycle: true, // 生命周期管理
      // 错误界面构建器（此处使用背景图片）
      errorBuilder: (_, __) => _backgroundImage,
      // 设置播放器占位图片
      placeholder: _backgroundImage,
      // 配置控制栏行为
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,  // 不显示控制器
      ),
      // 全屏后允许的设备方向
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      // 事件监听器
      eventListener: eventListener,
    );
  }
}
