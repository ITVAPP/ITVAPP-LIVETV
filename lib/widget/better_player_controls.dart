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

// 播放器配置类，管理视频播放和通知设置
class BetterPlayerConfig {
  // 背景图片Widget，用于播放器占位或错误界面
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover, // 覆盖整个区域
    gaplessPlayback: true, // 防止图片加载闪烁
    filterQuality: FilterQuality.medium, // 平衡质量与性能
  );

  // 默认通知图标路径
  static const String _defaultNotificationImage = 'logo.png';

  // 应用目录路径缓存键，与main.dart一致
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

  // 缓存请求头，避免重复生成
  static final Map<String, Map<String, String>> _headersCache = {};

  /// 清理请求头缓存，防止内存泄漏
  static void clearHeadersCache() {
    _headersCache.clear();
    LogUtil.i('播放器请求头缓存已清理');
  }

  /// 获取Logo存储目录，优先使用缓存
  static Future<Directory> _getLogoDirectory() async {
    if (_logoDirectory != null) return _logoDirectory!; // 返回缓存目录

    try {
      final appBasePath = SpUtil.getString(appDirectoryPathKey); // 读取缓存路径
      final String logoPath = appBasePath == null || appBasePath.isEmpty
          ? '${(await getApplicationDocumentsDirectory()).path}/channel_logos'
          : '$appBasePath/channel_logos'; // 构建Logo目录路径

      final logoDir = Directory(logoPath);
      if (!await logoDir.exists()) {
        await logoDir.create(recursive: true); // 创建目录
      }

      _logoDirectory = logoDir; // 缓存目录
      return logoDir;
    } catch (e, stackTrace) {
      LogUtil.logError('创建Logo目录失败', e, stackTrace); // 记录错误
      final fallbackDir = await getApplicationDocumentsDirectory(); // 获取备用目录
      final fallbackLogoDir = Directory('${fallbackDir.path}/channel_logos');

      if (!await fallbackLogoDir.exists()) {
        await fallbackLogoDir.create(recursive: true); // 创建备用目录
      }

      LogUtil.i('使用备用目录: ${fallbackDir.path}/channel_logos'); // 记录备用目录
      _logoDirectory = fallbackLogoDir; // 更新缓存
      return fallbackLogoDir;
    }
  }

  /// 从URL提取图片扩展名，默认png
  static String _getImageExtension(String url) {
    if (url.isEmpty) return 'png'; // 处理空URL

    try {
      final fileName = url.split('/').last.split('?').first; // 提取文件名
      final extensionMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(fileName);
      return extensionMatch?.group(1)?.toLowerCase() ?? 'png'; // 返回扩展名
    } catch (e) {
      LogUtil.e('提取图片扩展名失败: $e'); // 记录错误
      return 'png';
    }
  }

  /// 生成安全的文件名，基于频道标题和扩展名
  static String _generateSafeFileName(String channelTitle, String logoUrl) {
    final safeTitle = channelTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_'); // 清理标题
    final extension = _getImageExtension(logoUrl); // 获取扩展名
    return safeTitle.isNotEmpty ? '$safeTitle.$extension' : 'channel_${logoUrl.hashCode.abs()}.$extension'; // 返回安全文件名
  }

  /// 生成Logo唯一标识符
  static String _generateLogoIdentifier(String channelTitle, String logoUrl) {
    return '$channelTitle:${logoUrl.hashCode}'; // 组合标题和URL哈希
  }

  /// 检查本地Logo文件是否存在
  static Future<String?> _getLocalLogoPath(String channelTitle, String logoUrl) async {
    try {
      final fileName = _generateSafeFileName(channelTitle, logoUrl); // 生成文件名
      final logoDir = await _getLogoDirectory(); // 获取Logo目录
      final file = File('${logoDir.path}/$fileName');

      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 0 && fileSize <= _maxLogoFileSize) {
          LogUtil.i('本地Logo有效: ${file.path} (${fileSize ~/ 1024}KB)'); // 记录有效Logo
          return file.path;
        }
        await file.delete(); // 删除无效文件
        LogUtil.e('Logo文件无效，已删除: ${file.path} (${fileSize ~/ 1024}KB)'); // 记录删除
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查本地Logo失败', e, stackTrace); // 记录错误
    }
    return null;
  }

  /// 下载Logo并保存，防止重复下载
  static Future<void> _downloadLogoIfNeeded(String channelTitle, String logoUrl) async {
    if (logoUrl.isEmpty || !logoUrl.startsWith('http')) return; // 跳过无效URL

    final identifier = _generateLogoIdentifier(channelTitle, logoUrl); // 生成唯一标识
    if (_downloadingLogos.contains(identifier)) return; // 跳过正在下载

    try {
      if (await _getLocalLogoPath(channelTitle, logoUrl) != null) return; // 本地已有

      _downloadingLogos.add(identifier); // 标记下载
      final fileName = _generateSafeFileName(channelTitle, logoUrl); // 生成文件名
      final savePath = '${(await _getLogoDirectory()).path}/$fileName'; // 构建保存路径

      final result = await HttpUtil().downloadFile(
        logoUrl,
        savePath,
        progressCallback: (_) {}, // 空进度回调
      );

      if (result == HttpUtil.successStatusCode) {
        final file = File(savePath);
        final fileSize = await file.length();
        if (fileSize == 0 || fileSize > _maxLogoFileSize) {
          await file.delete(); // 删除无效文件
          LogUtil.e('下载Logo无效，已删除: $savePath (${fileSize ~/ 1024}KB)'); // 记录删除
        } else {
          LogUtil.i('Logo下载成功: $savePath (${fileSize ~/ 1024}KB)'); // 记录成功
        }
      } else {
        LogUtil.e('Logo下载失败，状态码: $result'); // 记录失败
      }
    } catch (e, stackTrace) {
      LogUtil.logError('下载Logo失败: $logoUrl', e, stackTrace); // 记录错误
    } finally {
      _downloadingLogos.remove(identifier); // 移除下载标记
    }
  }

  /// 检测视频URL格式
  static BetterPlayerVideoFormat _detectVideoFormat(String url) {
    if (url.isEmpty) return BetterPlayerVideoFormat.other; // 处理空URL

    final lowerCaseUrl = url.toLowerCase();
    if (lowerCaseUrl.contains('.m3u8')) {
      return BetterPlayerVideoFormat.hls; // 检测HLS格式
    }
    if (lowerCaseUrl.contains('.mpd')) {
      return BetterPlayerVideoFormat.dash; // 检测DASH格式
    }
    if (lowerCaseUrl.contains('.ism')) {
      return BetterPlayerVideoFormat.ss; // 检测SmoothStreaming格式
    }
    return BetterPlayerVideoFormat.other; // 默认格式
  }

  /// 获取通知图标路径
  static String _getNotificationImagePath() {
    try {
      final appBasePath = SpUtil.getString(appDirectoryPathKey); // 读取缓存路径
      if (appBasePath == null || appBasePath.isEmpty) {
        LogUtil.e('未找到缓存路径，使用默认图标'); // 记录错误
        return 'images/$_defaultNotificationImage';
      }

      final notificationFile = File('$appBasePath/images/$_defaultNotificationImage');
      if (notificationFile.existsSync() && notificationFile.lengthSync() > 0) {
        LogUtil.i('使用通知图标: ${notificationFile.path}'); // 记录有效图标
        return notificationFile.path;
      }
      LogUtil.e('通知图标无效: ${notificationFile.path}'); // 记录无效图标
    } catch (e) {
      LogUtil.e('获取通知图标路径失败: $e'); // 记录错误
    }
    return 'images/$_defaultNotificationImage'; // 返回默认图标
  }

  /// 创建播放器数据源
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
    String? channelTitle,
    String? channelLogo,
  }) {
    final validUrl = url.trim(); // 清理URL
    if (validUrl.isEmpty) LogUtil.e('数据源URL为空'); // 记录空URL

    // 使用缓存的请求头，避免重复生成
    final defaultHeaders = _headersCache[validUrl] ??= HeadersConfig.generateHeaders(url: validUrl);
    final mergedHeaders = {...defaultHeaders, ...?headers}; // 合并头信息

    final title = channelTitle?.isNotEmpty == true ? channelTitle! : S.current.appName; // 设置标题

    if (channelTitle != null && channelLogo?.startsWith('http') == true) {
      _downloadLogoIfNeeded(channelTitle, channelLogo!); // 下载Logo
    }

    final imageUrl = channelLogo?.startsWith('http') == true ? channelLogo! : _getNotificationImagePath(); // 设置通知图标

    final videoFormat = _detectVideoFormat(validUrl) != BetterPlayerVideoFormat.other
        ? _detectVideoFormat(validUrl)
        : (isHls ? BetterPlayerVideoFormat.hls : BetterPlayerVideoFormat.other); // 确定视频格式

    final liveStream = isHls || videoFormat == BetterPlayerVideoFormat.hls; // 判断是否直播

    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network, // 数据源类型：网络
      validUrl, // 视频URL
      videoFormat: videoFormat, // 视频格式（HLS、DASH等）
      liveStream: liveStream, // 是否为直播流
      useAsmsTracks: liveStream, // 启用自适应流轨道（直播）
      useAsmsAudioTracks: liveStream, // 启用自适应音频轨道（直播）
      useAsmsSubtitles: false, // 禁用自适应字幕
      headers: mergedHeaders.isNotEmpty ? mergedHeaders : null, // 请求头信息
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: true, // 显示通知
        title: title, // 通知标题
        author: S.current.appName, // 通知作者
        imageUrl: imageUrl, // 通知图标URL
        notificationChannelName: Config.packagename, // 通知渠道名称
        activityName: "MainActivity", // 通知点击跳转Activity
      ),
      bufferingConfiguration: BetterPlayerBufferingConfiguration(
        minBufferMs: liveStream ? 5000 : 10000, // 最小缓冲时长（毫秒）
        maxBufferMs: liveStream ? 5000 : 10000, // 最大缓冲时长（毫秒）
        bufferForPlaybackMs: liveStream ? 2000 : 5000, // 播放前缓冲时长（毫秒）
        bufferForPlaybackAfterRebufferMs: liveStream ? 2000 : 5000, // 重新缓冲后播放缓冲时长（毫秒）
      ),
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !liveStream, // 非直播启用缓存
        preCacheSize: _preCacheSize, // 预缓存大小
        maxCacheSize: _maxCacheSize, // 最大缓存大小
        maxCacheFileSize: _maxCacheFileSize, // 单文件最大缓存大小
      ),
    );
  }

  /// 创建播放器配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 视频适应容器
      autoPlay: false, // 禁用自动播放
      looping: !isHls, // 直播流不需要循环
      allowedScreenSleep: false, // 禁止屏幕休眠
      autoDispose: false, // 禁用自动销毁
      expandToFill: true, // 扩展填充容器
      handleLifecycle: true, // 处理生命周期
      errorBuilder: (_, __) => _backgroundImage, // 错误时显示背景图
      placeholder: _backgroundImage, // 占位图
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // 隐藏控制栏
      ),
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ], // 全屏后支持的屏幕方向
      eventListener: eventListener, // 事件监听
    );
  }
}
