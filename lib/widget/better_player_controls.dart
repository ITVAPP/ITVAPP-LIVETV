import 'dart:async';
import 'package:dio/dio.dart';
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

class BetterPlayerConfig {
  // 定义常量背景图片Widget，使用const构造器优化性能
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover, // 图片填充模式为覆盖
    gaplessPlayback: true, // 防止图片加载时闪烁
    filterQuality: FilterQuality.medium, // 平衡图片质量与性能
  );
  
  // 定义默认的通知图标路径
  static const String _defaultNotificationImage = 'assets/images/logo.png';

  /// 创建播放器数据源配置
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为HLS格式（直播流）
  /// - [headers]: 可选的HTTP请求头
  /// - [channelTitle]: 频道标题，用于通知栏显示
  /// - [channelLogo]: 频道LOGO路径，支持网络URL或本地资源
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
    String? channelTitle,
    String? channelLogo,
  }) {
    // 生成默认请求头并与传入头合并
    final defaultHeaders = HeadersConfig.generateHeaders(url: url);
    final mergedHeaders = {...defaultHeaders, ...?headers};
    
    // 配置通知栏信息
    final notificationConfiguration = BetterPlayerNotificationConfiguration(
      showNotification: true, // 启用通知栏显示
      title: channelTitle ?? S.current.appName, // 频道标题或默认应用名
      author: S.current.appName, // 设置通知作者为应用名
      imageUrl: channelLogo ?? _defaultNotificationImage, // 频道LOGO或默认图标
      notificationChannelName: Config.packagename, // Android通知渠道名称
      activityName: "itvapp_live_tv.MainActivity", // 指定通知跳转Activity
    );
    
    // 配置缓冲参数
    const bufferingConfiguration = BetterPlayerBufferingConfiguration(
      minBufferMs: 5000, // 最小缓冲5秒
      maxBufferMs: 20000, // 最大缓冲20秒
      bufferForPlaybackMs: 2500, // 播放所需缓冲2.5秒
      bufferForPlaybackAfterRebufferMs: 5000, // 重缓冲后播放所需5秒
    );
    
    // 配置缓存参数
    final cacheConfiguration = BetterPlayerCacheConfiguration(
      useCache: !isHls, // 非HLS启用缓存，避免直播流中断
      preCacheSize: 20 * 1024 * 1024, // 预缓存20MB
      maxCacheSize: 300 * 1024 * 1024, // 缓存总上限300MB
      maxCacheFileSize: 50 * 1024 * 1024, // 单文件缓存上限50MB
    );
    
    // 返回配置好的数据源
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network, // 网络数据源
      url, // 播放地址
      liveStream: isHls, // 是否为直播流
      useAsmsTracks: isHls, // HLS启用ASMS轨道
      useAsmsAudioTracks: isHls, // HLS启用ASMS音频轨道
      useAsmsSubtitles: false, // 禁用字幕以降低开销
      notificationConfiguration: notificationConfiguration, // 通知配置
      bufferingConfiguration: bufferingConfiguration, // 缓冲配置
      cacheConfiguration: cacheConfiguration, // 缓存配置
      headers: mergedHeaders.isNotEmpty ? mergedHeaders : null, // 附加请求头
    );
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 视频内容保持比例缩放
      autoPlay: false, // 禁用自动播放
      looping: isHls, // HLS启用循环播放
      allowedScreenSleep: false, // 禁止屏幕休眠
      autoDispose: false, // 禁用自动资源释放
      expandToFill: true, // 填充可用空间
      handleLifecycle: true, // 启用生命周期管理
      errorBuilder: (_, __) => _backgroundImage, // 错误时显示背景图
      placeholder: _backgroundImage, // 加载时显示占位图
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // 隐藏控制栏
      ),
      deviceOrientationsAfterFullScreen: [ // 全屏退出后支持的屏幕方向
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      eventListener: eventListener, // 注册事件监听器
    );
  }
}

/// EPG通知更新辅助类，管理EPG数据加载和通知栏节目信息更新
class EpgNotificationHelper {
  // 存储当前节目标题，键为频道标识
  static final Map<String, String> _currentProgramTitles = {};
  // 存储节目检查定时器，键为频道标识
  static final Map<String, Timer> _programCheckTimers = {};
  // 存储请求取消令牌，键为频道标识
  static final Map<String, CancelToken> _cancelTokens = {};
  
  // 线程同步锁，确保多线程安全
  static final Object _lock = Object();
  
  // EPG加载延迟2秒
  static const Duration _epgLoadDelay = Duration(milliseconds: 2000);
  // 默认节目检查间隔（分钟）
  static const Duration _defaultCheckInterval = Duration(minutes: 5);
  // EPG请求超时（秒）
  static const Duration _epgRequestTimeout = Duration(seconds: 18);
  
  /// 检查播放器是否有效
  static bool _isPlayerValid(BetterPlayerController? controller, String channelKey) {
    if (controller == null || controller.isDisposed()) {
      LogUtil.i('操作失败: 播放器无效或已销毁, 频道: $channelKey');
      return false;
    }
    return true;
  }
  
  // 记录最后活跃频道键，用于频道切换清理
  static String? _lastActiveChannelKey;
  
  /// 启动EPG节目通知更新
  static void startEpgNotificationUpdate(
    BetterPlayerController playerController,
    String? channelTitle,
    String url,
  ) {
    // 使用频道标题或URL作为频道标识
    final String channelKey = channelTitle ?? url;
    
    if (!_isPlayerValid(playerController, channelKey)) return;
    
    // 同步操作，确保线程安全
    synchronized(_lock, () {
      // 清理旧频道资源
      if (_lastActiveChannelKey != null && _lastActiveChannelKey != channelKey) {
        LogUtil.i('频道切换: 从 $_lastActiveChannelKey 到 $channelKey');
        _cancelExistingRequests(_lastActiveChannelKey!);
      }
      
      _lastActiveChannelKey = channelKey; // 更新活跃频道
      _cancelExistingRequests(channelKey); // 取消当前频道请求
      _cancelTokens[channelKey] = CancelToken(); // 创建新取消令牌
    });
    
    // 创建简化的PlayModel用于EPG请求
    final simpleModel = PlayModel(title: channelTitle, url: url);
    
    // 延迟加载EPG，降低初始化资源竞争
    Future.delayed(_epgLoadDelay, () {
      if (_isPlayerValid(playerController, channelKey)) {
        _loadEpgData(playerController, simpleModel, channelKey, _cancelTokens[channelKey]);
      }
    });
  }
  
  /// 取消指定频道的现有请求和定时器
  static void _cancelExistingRequests(String channelKey) {
    // 取消EPG请求
    if (_cancelTokens.containsKey(channelKey)) {
      _cancelTokens[channelKey]?.cancel('启动新的EPG请求');
      _cancelTokens.remove(channelKey);
    }
    
    // 取消定时器
    if (_programCheckTimers.containsKey(channelKey)) {
      _programCheckTimers[channelKey]?.cancel();
      _programCheckTimers.remove(channelKey);
    }
  }
  
  /// 加载EPG数据并处理结果
  static Future<void> _loadEpgData(
    BetterPlayerController playerController,
    PlayModel playModel, 
    String channelKey,
    CancelToken? cancelToken
  ) async {
    if (!_isPlayerValid(playerController, channelKey)) return;
    
    try {
      // 请求EPG数据，设置超时
      final epgModel = await EpgUtil.getEpg(playModel, cancelToken: cancelToken)
          .timeout(_epgRequestTimeout, onTimeout: () {
        LogUtil.i('EPG请求超时, 频道: $channelKey');
        return null;
      });
      
      if (epgModel != null && epgModel.epgData != null && epgModel.epgData!.isNotEmpty) {
        // 更新节目信息
        _updateCurrentProgram(playerController, channelKey, playModel, epgModel);
      } else {
        LogUtil.i('未获取到有效EPG数据, 频道: $channelKey');
        // 设置默认检查定时器
        _scheduleDefaultCheck(playerController, channelKey, playModel);
      }
    } catch (e, stackTrace) {
      if (e is DioError && e.type == DioErrorType.cancel) {
        LogUtil.i('EPG请求已取消, 频道: $channelKey');
      } else {
        LogUtil.logError('加载EPG数据失败: $channelKey', e, stackTrace);
        // 设置默认检查定时器重试
        _scheduleDefaultCheck(playerController, channelKey, playModel);
      }
    }
  }
  
  /// 设置默认节目检查定时器
  static void _scheduleDefaultCheck(
    BetterPlayerController playerController,
    String channelKey, 
    PlayModel playModel
  ) {
    synchronized(_lock, () {
      _programCheckTimers[channelKey]?.cancel(); // 取消现有定时器
      // 创建新定时器，定期重试EPG
      _programCheckTimers[channelKey] = Timer(_defaultCheckInterval, () {
        if (_isPlayerValid(playerController, channelKey)) {
          _loadEpgData(playerController, playModel, channelKey, _cancelTokens[channelKey]);
        } else {
          dispose(channelKey); // 释放资源
        }
      });
    });
  }
  
  /// 更新当前节目信息并安排下次更新
  static void _updateCurrentProgram(
    BetterPlayerController playerController,
    String channelKey, 
    PlayModel playModel,
    EpgModel epgModel
  ) {
    if (!_isPlayerValid(playerController, channelKey) || 
        epgModel.epgData == null || 
        epgModel.epgData!.isEmpty) return;
    
    final now = DateTime.now();
    final today = DateUtil.formatDate(now, format: "yyyy-MM-dd"); // 当前日期
    EpgData? currentProgram; // 当前节目
    DateTime? nextProgramStartTime; // 下次更新时间
    
    for (final program in epgModel.epgData!) {
      if (program.start == null || program.end == null || program.title == null) continue;
      
      try {
        // 解析节目时间
        DateTime startTime = DateUtil.parseDateTime('$today ${program.start}');
        DateTime endTime = DateUtil.parseDateTime('$today ${program.end}');
        
        // 处理跨日节目
        if (endTime.isBefore(startTime)) {
          endTime = endTime.add(const Duration(days: 1));
        }
        
        // 处理昨天开始的节目
        if (startTime.isAfter(now) && program.start!.compareTo(program.end!) > 0) {
          startTime = startTime.subtract(const Duration(days: 1));
        }
        
        // 确定当前节目
        if (now.isAfter(startTime) && now.isBefore(endTime)) {
          currentProgram = program;
          nextProgramStartTime = endTime; // 设置下次更新为节目结束
          break;
        }
        
        // 记录最近的未来节目时间
        if (now.isBefore(startTime) && (nextProgramStartTime == null || startTime.isBefore(nextProgramStartTime))) {
          nextProgramStartTime = startTime;
        }
      } catch (e) {
        LogUtil.e('解析节目时间失败: ${program.start}-${program.end}, 错误=$e');
        continue;
      }
    }
    
    // 比较节目标题是否有变化
    String oldProgramTitle = _currentProgramTitles[channelKey] ?? S.current.appName;
    String newProgramTitle = currentProgram?.title ?? S.current.appName;
    
    // 更新通知栏
    if (oldProgramTitle != newProgramTitle) {
      synchronized(_lock, () {
        _currentProgramTitles[channelKey] = newProgramTitle; // 更新节目标题
      });
      _updateNotification(playerController, channelKey, newProgramTitle); // 更新通知
    }
    
    // 安排下次更新
    _scheduleNextUpdate(playerController, channelKey, playModel, nextProgramStartTime);
  }
  
  /// 计算并设置下次节目更新定时器
  static void _scheduleNextUpdate(
    BetterPlayerController playerController,
    String channelKey,
    PlayModel playModel,
    DateTime? nextUpdateTime
  ) {
    Duration delay; // 下次更新延迟
    final now = DateTime.now();
    
    if (nextUpdateTime != null && nextUpdateTime.difference(now).inMilliseconds > 0) {
      delay = nextUpdateTime.difference(now); // 使用节目时间计算延迟
    } else {
      delay = _defaultCheckInterval; // 使用默认间隔
    }
    
    synchronized(_lock, () {
      _programCheckTimers[channelKey]?.cancel(); // 取消现有定时器
      // 创建新定时器
      _programCheckTimers[channelKey] = Timer(delay, () {
        if (_isPlayerValid(playerController, channelKey)) {
          _loadEpgData(playerController, playModel, channelKey, _cancelTokens[channelKey]);
        } else {
          dispose(channelKey); // 释放资源
        }
      });
    });
  }
  
  /// 安全更新通知栏节目信息
  static void _updateNotification(
    BetterPlayerController playerController,
    String channelKey,
    String programTitle
  ) {
    if (!_isPlayerValid(playerController, channelKey)) return;
    
    try {
      final dataSource = playerController.betterPlayerDataSource;
      if (dataSource == null || dataSource.notificationConfiguration == null) {
        LogUtil.i('更新通知失败: 数据源或通知配置为空, 频道: $channelKey');
        return;
      }
      
      // 更新通知栏，仅修改节目标题
      final config = dataSource.notificationConfiguration!;
      playerController.updateNotificationConfiguration(
        title: config.title,
        author: programTitle,
        imageUrl: config.imageUrl,
      );
      
      LogUtil.i('通知栏更新: $programTitle, 频道: $channelKey');
    } catch (e, stackTrace) {
      LogUtil.logError('更新通知栏失败: $channelKey', e, stackTrace);
    }
  }
  
  /// 执行同步操作，确保线程安全
  static void synchronized(Object lock, void Function() action) {
    action(); // 简化处理，依赖Dart单线程模型
  }
  
  /// 清理指定频道或所有资源
  static void dispose(String? channelKey) {
    synchronized(_lock, () {
      if (channelKey != null) {
        // 清理指定频道资源
        _programCheckTimers[channelKey]?.cancel();
        _programCheckTimers.remove(channelKey);
        _cancelTokens[channelKey]?.cancel('资源销毁');
        _cancelTokens.remove(channelKey);
        _currentProgramTitles.remove(channelKey);
        LogUtil.i('清理频道资源: $channelKey');
      } else {
        // 清理所有资源
        _programCheckTimers.values.forEach((timer) => timer.cancel());
        _cancelTokens.values.forEach((token) => token.cancel('资源销毁'));
        _programCheckTimers.clear();
        _cancelTokens.clear();
        _currentProgramTitles.clear();
        LogUtil.i('清理所有频道资源');
      }
    });
  }
}
