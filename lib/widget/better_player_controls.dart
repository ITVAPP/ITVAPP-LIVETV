import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 播放器配置类，管理视频播放和通知设置
class BetterPlayerConfig {
  // 背景图片Widget，用于播放器占位或错误界面
  static Widget get _backgroundImage => const Image(
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

  // Logo目录初始化保护，避免多线程重复初始化
  static Completer<Directory>? _logoDirectoryCompleter;

  // 防止重复下载Logo的映射表，使用Completer确保同一Logo只下载一次
  static final Map<String, Completer<void>> _downloadCompleters = {};

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

  /// 获取Logo存储目录，优先使用缓存，确保线程安全的单次初始化
  static Future<Directory> _getLogoDirectory() async {
    // 如果已经初始化，直接返回
    if (_logoDirectory != null) return _logoDirectory!;

    // 如果正在初始化，等待完成
    if (_logoDirectoryCompleter != null) {
      return _logoDirectoryCompleter!.future;
    }

    // 开始初始化过程
    _logoDirectoryCompleter = Completer<Directory>();

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
      _logoDirectoryCompleter!.complete(logoDir);
      return logoDir;
    } catch (e, stackTrace) {
      LogUtil.logError('创建Logo目录失败', e, stackTrace); // 记录错误
      
      try {
        final fallbackDir = await getApplicationDocumentsDirectory(); // 获取备用目录
        final fallbackLogoDir = Directory('${fallbackDir.path}/channel_logos');

        if (!await fallbackLogoDir.exists()) {
          await fallbackLogoDir.create(recursive: true); // 创建备用目录
        }

        LogUtil.i('使用备用目录: ${fallbackDir.path}/channel_logos'); // 记录备用目录
        _logoDirectory = fallbackLogoDir; // 更新缓存
        _logoDirectoryCompleter!.complete(fallbackLogoDir);
        return fallbackLogoDir;
      } catch (fallbackError, fallbackStackTrace) {
        LogUtil.logError('创建备用Logo目录也失败', fallbackError, fallbackStackTrace);
        _logoDirectoryCompleter!.completeError(fallbackError);
        _logoDirectoryCompleter = null;
        rethrow;
      }
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

  /// 下载Logo并保存
  static Future<void> _downloadLogoIfNeeded(String channelTitle, String logoUrl) async {
    if (logoUrl.isEmpty || !logoUrl.startsWith('http')) return; // 跳过无效URL

    final identifier = _generateLogoIdentifier(channelTitle, logoUrl); // 生成唯一标识

    // 如果正在下载，等待完成
    if (_downloadCompleters.containsKey(identifier)) {
      return _downloadCompleters[identifier]!.future;
    }

    // 检查本地是否已存在
    if (await _getLocalLogoPath(channelTitle, logoUrl) != null) return;

    // 开始下载过程
    final completer = Completer<void>();
    _downloadCompleters[identifier] = completer;

    try {
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

      completer.complete();
    } catch (e, stackTrace) {
      LogUtil.logError('下载Logo失败: $logoUrl', e, stackTrace); // 记录错误
      completer.completeError(e);
    } finally {
      _downloadCompleters.remove(identifier); // 清理完成器
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
    bool isTV = false, // 新增TV标识参数
  }) {
    final validUrl = url.trim(); // 清理URL
    if (validUrl.isEmpty) LogUtil.e('数据源URL为空'); // 记录空URL

    // 使用缓存的请求头，避免重复生成
    final defaultHeaders = _headersCache[validUrl] ??= HeadersConfig.generateHeaders(url: validUrl);
    final mergedHeaders = {...defaultHeaders, ...?headers}; // 合并头信息

    final title = channelTitle?.isNotEmpty == true ? channelTitle! : S.current.appName; // 设置标题

    // TV模式下跳过Logo下载
    if (!isTV && channelTitle != null && channelLogo?.startsWith('http') == true) {
      _downloadLogoIfNeeded(channelTitle, channelLogo!); // 下载Logo
    }

    // TV模式下使用简化的通知配置
    final String imageUrl;
    if (isTV) {
      // TV模式：不需要实际的通知图标，使用默认值
      imageUrl = 'images/$_defaultNotificationImage';
      LogUtil.i('TV模式：跳过Logo下载和通知图标处理');
    } else {
      // 非TV模式：正常处理通知图标
      imageUrl = channelLogo?.startsWith('http') == true ? channelLogo! : _getNotificationImagePath();
    }

    // 完全基于URL检测格式，外部参数仅保留接口兼容性
    final videoFormat = _detectVideoFormat(validUrl); // 确定视频格式
    final liveStream = videoFormat == BetterPlayerVideoFormat.hls; // 基于URL检测结果判断是否直播

    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network, // 数据源类型：网络
      validUrl, // 视频URL
      // videoFormat: videoFormat, // 视频格式（HLS、DASH等）
      liveStream: liveStream, // 是否为直播流
      useAsmsTracks: liveStream, // 启用自适应流轨道（直播）
      useAsmsAudioTracks: liveStream, // 启用自适应音频轨道（直播）
      useAsmsSubtitles: false, // 禁用自适应字幕
      headers: mergedHeaders.isNotEmpty ? mergedHeaders : null, // 请求头信息
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: !isTV, // TV模式下禁用通知
        title: title, // 通知标题
        author: S.current.appName, // 通知作者
        imageUrl: imageUrl, // 通知图标URL
        notificationChannelName: Config.packagename, // 通知渠道名称
        activityName: "MainActivity", // 通知点击跳转Activity
      ),
      bufferingConfiguration: BetterPlayerBufferingConfiguration(
        // 统一min和max值，避免突发式缓冲行为，减少状态切换
        minBufferMs: liveStream ? 15000 : 20000,
        maxBufferMs: liveStream ? 15000 : 30000,      // HLS: 设置相同避免突发式缓冲
        bufferForPlaybackMs: liveStream ? 3000 : 3000,         // 播放前缓冲
        bufferForPlaybackAfterRebufferMs: liveStream ? 6000 : 6000,  // 重新缓冲后）
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
    String? url, // 新增URL参数，用于更准确的格式检测
  }) {
    // 优先基于URL检测格式，外部参数仅作fallback
    final bool isLiveStream;
    if (url != null && url.trim().isNotEmpty) {
      final detectedFormat = _detectVideoFormat(url.trim());
      isLiveStream = detectedFormat == BetterPlayerVideoFormat.hls;
    } else {
      isLiveStream = isHls; // 无URL时回退到外部参数
    }

    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 视频适应容器
      autoPlay: false, // 禁用自动播放
      looping: !isLiveStream, // 基于检测结果：直播流不需要循环
      allowedScreenSleep: false, // 禁止屏幕休眠
      autoDispose: false, // 禁用自动销毁
      expandToFill: true, // 扩展填充容器
      handleLifecycle: true, // 处理生命周期
      errorBuilder: (_, __) => _backgroundImage, // 错误时显示背景图
      placeholder: _backgroundImage, // 占位图
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // 隐藏控制栏
        enableSubtitles: false, // 禁用字幕功能
        enableQualities: false, // 禁用质量选择
        enableAudioTracks: false, // 禁用音轨选择  
        enableFullscreen: false, // 禁用全屏按钮
        enableMute: false, // 禁用静音按钮
        enablePlayPause: false, // 禁用播放暂停按钮
        enableProgressBar: false, // 禁用进度条
        enableProgressText: false, // 禁用进度文本
        enableSkips: false, // 禁用跳过按钮
        enableOverflowMenu: false, // 禁用溢出菜单
        showControlsOnInitialize: false, // 初始化时不显示控制栏
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
