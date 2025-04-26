import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:dio/dio.dart';

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

  /// 创建播放器数据源配置
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为 HLS 格式（直播流）
  /// - [headers]: 可选的HTTP请求头
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
    
    // 提取公共的 BetterPlayerDataSource 配置
    final baseDataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls, // 根据 URL 判断是否为直播流
      useAsmsTracks: isHls, // 启用 ASMS 音视频轨道，非 HLS 时关闭以减少资源占用
      useAsmsAudioTracks: isHls, // 同上
      useAsmsSubtitles: false, // 禁用字幕以降低播放开销
      // 配置系统通知栏行为
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: true,
        title: channelTitle ?? S.current.appName, // 使用传入的频道标题或默认值
        author: S.current.appName, // 添加作者/来源信息
        imageUrl: channelLogo ?? _defaultNotificationImage, // 频道LOGO URL或默认图像
        notificationChannelName: Config.packagename, // Android通知渠道名称
        activityName: "itvapp_live_tv.MainActivity", 
      ),
      // 缓冲配置
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000, // 5 秒
        maxBufferMs: 20000, // 20 秒
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      // 缓存配置
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls, // 非 HLS 启用缓存（直播流缓存可能导致中断）
        preCacheSize: 20 * 1024 * 1024, // 预缓存大小（10MB）
        maxCacheSize: 300 * 1024 * 1024, // 缓存总大小限制（300MB）
        maxCacheFileSize: 50 * 1024 * 1024, // 单个缓存文件大小限制（50MB）
      ),
    );
    
    // 根据 mergedHeaders 是否为空返回实例
    return mergedHeaders.isNotEmpty
        ? BetterPlayerDataSource(
            baseDataSource.type,
            baseDataSource.url,
            liveStream: baseDataSource.liveStream,
            useAsmsTracks: baseDataSource.useAsmsTracks,
            useAsmsAudioTracks: baseDataSource.useAsmsAudioTracks,
            useAsmsSubtitles: baseDataSource.useAsmsSubtitles,
            notificationConfiguration: baseDataSource.notificationConfiguration,
            bufferingConfiguration: baseDataSource.bufferingConfiguration,
            cacheConfiguration: baseDataSource.cacheConfiguration,
            headers: mergedHeaders, // 包含 headers
          )
        : baseDataSource; // 不包含 headers，直接使用基础配置
  }

  /// 创建播放器基本配置
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

/// EPG通知更新辅助类
/// 负责处理EPG数据加载和通知栏节目信息更新
class EpgNotificationHelper {
  // 存储当前节目信息的静态变量
  static Map<String, String> _currentProgramTitles = {};
  // 存储节目检查定时器
  static Map<String, Timer> _programCheckTimers = {};
  // 存储EPG数据
  static Map<String, EpgModel> _epgDataCache = {};
  // 存储请求取消令牌
  static Map<String, CancelToken> _cancelTokens = {};
  
  /// 启动EPG节目通知更新
  /// - [playerController]: 播放器控制器
  /// - [channelTitle]: 频道标题，用于获取EPG和作为缓存键
  /// - [url]: 视频播放地址，作为备用标识符
  static void startEpgNotificationUpdate(
    BetterPlayerController playerController,
    String? channelTitle,
    String url,
  ) {
    if (playerController.isDisposed()) {
      LogUtil.i('启动EPG通知更新失败: 播放器已销毁');
      return;
    }
    
    // 设置频道标识符，优先使用channelTitle，否则使用URL
    final String channelKey = channelTitle ?? url;
    
    // 先取消之前的请求（如果存在）
    _cancelTokens[channelKey]?.cancel('启动新的EPG请求');
    _cancelTokens[channelKey] = CancelToken();
    
    // 延迟2000毫秒加载EPG数据
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (playerController.isDisposed()) {
        LogUtil.i('加载EPG数据失败: 播放器已销毁, 频道: $channelKey');
        return;
      }
      
      // 创建简单的PlayModel用于请求EPG
      final simpleModel = PlayModel(
        title: channelTitle,
        url: url,
      );
      _loadEpgData(playerController, simpleModel, channelKey, _cancelTokens[channelKey]);
    });
  }
  
  /// 加载EPG数据
  static Future<void> _loadEpgData(
    BetterPlayerController playerController,
    PlayModel playModel, 
    String channelKey,
    CancelToken? cancelToken
  ) async {
    if (playerController.isDisposed()) {
      LogUtil.i('加载EPG数据失败: 播放器已销毁, 频道: $channelKey');
      return;
    }
    
    try {
      // 请求EPG数据
      final epgModel = await EpgUtil.getEpg(
        playModel,
        cancelToken: cancelToken
      );
      
      if (epgModel != null && epgModel.epgData != null && epgModel.epgData!.isNotEmpty) {
        // 缓存EPG数据
        _epgDataCache[channelKey] = epgModel;
        
        // 更新当前节目信息
        _updateCurrentProgram(playerController, channelKey, playModel);
        
        // 设置定时器定期检查节目更新
        _startProgramCheckTimer(playerController, channelKey, playModel);
      } else {
        LogUtil.i('未获取到有效EPG数据, 频道: $channelKey');
      }
    } catch (e, stackTrace) {
      if (e is DioError && (e.type == DioErrorType.cancel)) {
        LogUtil.i('EPG请求已取消, 频道: $channelKey');
      } else {
        LogUtil.logError('加载EPG数据失败: $channelKey', e, stackTrace);
      }
    }
  }
  
  /// 更新当前正在播放的节目信息
  static void _updateCurrentProgram(
    BetterPlayerController playerController,
    String channelKey, 
    PlayModel playModel
  ) {
    if (playerController.isDisposed()) {
      LogUtil.i('更新节目信息失败: 播放器已销毁, 频道: $channelKey');
      return;
    }
    
    final epgModel = _epgDataCache[channelKey];
    if (epgModel == null || epgModel.epgData == null || epgModel.epgData!.isEmpty) {
      LogUtil.i('更新节目信息失败: 无有效EPG数据, 频道: $channelKey');
      return;
    }
    
    final now = DateTime.now();
    final today = DateUtil.formatDate(now, format: "yyyy-MM-dd");
    
    // 查找当前正在播放的节目
    EpgData? currentProgram;
    DateTime? nextProgramStartTime;
    
    for (final program in epgModel.epgData!) {
      if (program.start == null || program.end == null || program.title == null) continue;
      
      try {
        final startTime = DateUtil.parseDateTime('$today ${program.start}');
        final endTime = DateUtil.parseDateTime('$today ${program.end}');
        
        // 如果当前时间在节目开始和结束时间之间，则为当前节目
        if (now.isAfter(startTime) && now.isBefore(endTime)) {
          currentProgram = program;
          // 记录下一次更新的时间（节目结束时间）
          nextProgramStartTime = endTime;
          break;
        }
        
        // 如果节目还未开始，记录最近的一个节目开始时间
        if (now.isBefore(startTime) && (nextProgramStartTime == null || startTime.isBefore(nextProgramStartTime))) {
          nextProgramStartTime = startTime;
        }
      } catch (e) {
        LogUtil.e('解析节目时间失败: ${program.start}-${program.end}, 错误=$e');
        continue;
      }
    }
    
    // 检查节目是否有更新
    String oldProgramTitle = _currentProgramTitles[channelKey] ?? S.current.appName;
    String newProgramTitle = S.current.appName;
    
    if (currentProgram != null && currentProgram.title != null) {
      newProgramTitle = currentProgram.title!;
    }
    
    // 仅当节目发生变化时才更新通知栏
    if (oldProgramTitle != newProgramTitle) {
      _currentProgramTitles[channelKey] = newProgramTitle;
      LogUtil.i('节目已更新: $newProgramTitle, 频道: $channelKey');
      
      // 安全地更新通知栏
      _updateNotification(playerController, channelKey, newProgramTitle);
    }
    
    // 如果有下一个节目开始/结束时间，计算下一次更新的延迟
    if (nextProgramStartTime != null) {
      final delayMillis = nextProgramStartTime.difference(now).inMilliseconds;
      if (delayMillis > 0) {
        // 取消当前定时器
        _programCheckTimers[channelKey]?.cancel();
        
        // 创建新定时器，在下一个节目变更时更新
        _programCheckTimers[channelKey] = Timer(Duration(milliseconds: delayMillis), () {
          if (!playerController.isDisposed()) {
            _updateCurrentProgram(playerController, channelKey, playModel);
          }
        });
        
        LogUtil.i('设置下一次节目更新: ${DateUtil.formatDate(nextProgramStartTime, format: "HH:mm:ss")}, 频道: $channelKey');
      } else {
        // 如果下一个更新时间已经过去，立即安排一个更新
        _startProgramCheckTimer(playerController, channelKey, playModel);
      }
    } else {
      // 如果没有找到下一个更新时间，使用周期性更新
      _startProgramCheckTimer(playerController, channelKey, playModel);
    }
  }
  
  /// 安全地更新通知栏信息，不影响播放
  static void _updateNotification(
    BetterPlayerController playerController,
    String channelKey,
    String programTitle
  ) {
    if (playerController.isDisposed()) {
      LogUtil.i('更新通知栏失败: 播放器已销毁, 频道: $channelKey');
      return;
    }
    
    try {
      // 获取当前播放器数据源
      final dataSource = playerController.betterPlayerDataSource;
      if (dataSource == null) {
        LogUtil.i('更新通知栏失败: 数据源为空, 频道: $channelKey');
        return;
      }
      
      // 获取当前通知配置
      final notificationConfig = dataSource.notificationConfiguration;
      if (notificationConfig == null) {
        LogUtil.i('更新通知栏失败: 通知配置为空, 频道: $channelKey');
        return;
      }
      
      // 直接调用BetterPlayer的通知更新方法
      // 只更新author字段，保持其他字段不变
      playerController.updateNotificationConfiguration(
        title: notificationConfig.title,
        author: programTitle,
        imageUrl: notificationConfig.imageUrl,
      );
      
      LogUtil.i('通知栏已更新: $programTitle, 频道: $channelKey');
    } catch (e, stackTrace) {
      LogUtil.logError('更新通知栏失败: $channelKey', e, stackTrace);
    }
  }
  
  /// 开始定时检查节目更新
  static void _startProgramCheckTimer(
    BetterPlayerController playerController,
    String channelKey, 
    PlayModel playModel
  ) {
    // 先取消现有定时器
    _programCheckTimers[channelKey]?.cancel();
    
    // 创建备用定时器，每10分钟检查一次节目更新
    _programCheckTimers[channelKey] = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (!playerController.isDisposed()) {
        _updateCurrentProgram(playerController, channelKey, playModel);
      } else {
        // 如果播放器已销毁，取消定时器
        timer.cancel();
        _programCheckTimers.remove(channelKey);
      }
    });
  }
  
  /// 清理资源
  static void dispose(String? channelKey) {
    if (channelKey != null) {
      // 清理特定频道的资源
      _programCheckTimers[channelKey]?.cancel();
      _programCheckTimers.remove(channelKey);
      _cancelTokens[channelKey]?.cancel('资源销毁');
      _cancelTokens.remove(channelKey);
      _epgDataCache.remove(channelKey);
      _currentProgramTitles.remove(channelKey);
      LogUtil.i('已清理频道资源: $channelKey');
    } else {
      // 清理所有资源
      for (var timer in _programCheckTimers.values) {
        timer.cancel();
      }
      for (var token in _cancelTokens.values) {
        token.cancel('资源销毁');
      }
      _programCheckTimers.clear();
      _cancelTokens.clear();
      _epgDataCache.clear();
      _currentProgramTitles.clear();
      LogUtil.i('已清理所有频道资源');
    }
  }
}
