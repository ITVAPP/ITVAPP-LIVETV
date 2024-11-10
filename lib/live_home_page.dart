import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'channel_drawer_page.dart';
import 'mobile_video_widget.dart';
import 'table_video_widget.dart';
import 'tv/tv_page.dart';
import 'util/env_util.dart';
import 'util/check_version_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'util/dialog_util.dart';
import 'util/custom_snackbar.dart';
import 'util/channel_util.dart';
import 'util/traffic_analytics.dart';
import 'widget/empty_page.dart';
import 'widget/show_exit_confirm.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

/// 音视频分离流处理器类
class SeparatedStreamHandler {
  VideoPlayerController? _videoController;
  VideoPlayerController? _audioController;
  Timer? _syncTimer;
  
  // YouTube请求所需的标准头部
  static final Map<String, String> _youtubeHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  };
  
// 检查是否为分离流
Future<bool> isSeparatedStream(String url) async {

  if (!url.endsWith('.m3u8')) {
    LogUtil.i('URL不是m3u8格式，跳过检查');
    return false;
  }
  
  try {
    LogUtil.i('正在发送HTTP请求获取m3u8内容...');
    LogUtil.i('请求头: $_youtubeHeaders');
    
    final response = await http.get(
      Uri.parse(url),
      headers: _youtubeHeaders
    ).timeout(const Duration(seconds: 10));
    
    LogUtil.i('HTTP响应状态码: ${response.statusCode}');
    
    if (response.statusCode != 200) {
      LogUtil.e('HTTP请求失败，状态码: ${response.statusCode}');
      return false;
    }
    
    final content = response.body;
    LogUtil.i('获取到m3u8内容，长度: ${content.length}字节');
    
    // 检查是否包含YouTube的音频和视频流标记
    bool hasAudioStream = content.contains('itag=140') || content.contains('AUDIO.*itag/140');
    bool hasVideoStream = content.contains(RegExp(r'itag=(13[6-9]|9[5-9]|24[0-9]|25[0-9])')) || 
                         content.contains(RegExp(r'VIDEO.*itag/(13[6-9]|9[5-9]|24[0-9]|25[0-9])'));
    
    final result = hasAudioStream && hasVideoStream;
    LogUtil.i('最终检测结果: ${result ? "是" : "不是"}分离流');
    
    return result;
  } catch (e, stackTrace) {
    LogUtil.logError('检查YouTube分离流时出错', e, stackTrace);
    return false;
  }
}

// 提取音视频流地址
Future<Map<String, String>> extractStreams(String m3u8Content) async {
  LogUtil.i('m3u8内容长度: ${m3u8Content.length}字节');
  
  final lines = m3u8Content.split('\n');
  
  String? audioUrl;
  String? videoUrl;
  int validLineCount = 0;
  
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    
    validLineCount++;
    
    // 扩展视频格式支持
    if (line.contains('itag=140') || line.contains('AUDIO.*itag/140')) {
      audioUrl = line;
      LogUtil.i('音频URL: ${audioUrl.length > 100 ? "${audioUrl.substring(0, 100)}..." : audioUrl}');
    } else if (line.contains(RegExp(r'itag=(13[6-9]|9[5-9]|24[0-9]|25[0-9])')) ||
               line.contains(RegExp(r'VIDEO.*itag/(13[6-9]|9[5-9]|24[0-9]|25[0-9])'))) {
      videoUrl = line;
      LogUtil.i('视频URL: ${videoUrl.length > 100 ? "${videoUrl.substring(0, 100)}..." : videoUrl}');
    }
  }

  LogUtil.i('音频流: ${audioUrl != null ? "已找到" : "未找到"}');
  LogUtil.i('视频流: ${videoUrl != null ? "已找到" : "未找到"}');

  if (videoUrl == null) {
    LogUtil.e('未能找到视频流，抛出异常');
    throw Exception('无法提取YouTube视频流地址');
  }

  final result = {
    'video': videoUrl,
    'audio': audioUrl ?? '',
  };
  
  LogUtil.i('提取结果: ${result.toString()}');
  return result;
}

  // 初始化播放器
  Future<VideoPlayerController> initialize(String url, Map<String, String> headers) async {
    try {
      // 合并用户提供的headers和YouTube必需的headers
      final combinedHeaders = {..._youtubeHeaders, ...headers};
      
      final response = await http.get(
        Uri.parse(url),
        headers: combinedHeaders
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        throw Exception('获取YouTube流媒体列表失败');
      }

      final streams = await extractStreams(response.body);
      
      // 初始化视频控制器
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(streams['video']!),
        httpHeaders: combinedHeaders,
        formatHint: VideoFormat.hls,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      // 如果存在音频流，初始化音频控制器
      if (streams['audio']!.isNotEmpty) {
        _audioController = VideoPlayerController.networkUrl(
          Uri.parse(streams['audio']!),
          httpHeaders: combinedHeaders,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );

        await _audioController!.initialize();
        _setupSyncTimer();
      }

      await _videoController!.initialize();
      return _videoController!;

    } catch (e) {
      await dispose();
      rethrow;
    }
  }

  // 设置同步计时器
  void _setupSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _synchronizePlayback();
    });
  }

  // 同步音视频播放
  void _synchronizePlayback() {
    if (_videoController == null || _audioController == null) return;

    if (_videoController!.value.isPlaying != _audioController!.value.isPlaying) {
      if (_videoController!.value.isPlaying) {
        _audioController!.play();
      } else {
        _audioController!.pause();
      }
    }

    final videoDuration = _videoController!.value.position;
    final audioDuration = _audioController!.value.position;
    if ((videoDuration - audioDuration).abs() > const Duration(milliseconds: 100)) {
      _audioController!.seekTo(videoDuration);
    }
  }

  // 资源释放
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _syncTimer = null;

    if (_audioController != null) {
      await _audioController!.dispose();
      _audioController = null;
    }

    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }
  }
}

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 新增：分离流处理器实例
  final SeparatedStreamHandler _separatedStreamHandler = SeparatedStreamHandler();

  // 超时重试次数
  static const int defaultMaxRetries = 1;
  // 超时检测的时间
  static const int defaultTimeoutSeconds = 18;
  
  // 新增重试相关的状态管理
  bool _isRetrying = false;
  Timer? _retryTimer;
  
  // 存储加载状态的提示文字
  String toastString = S.current.loading;

  // 视频播放列表的数据模型
  PlaylistModel? _videoMap;

  // 当前播放的频道数据模型
  PlayModel? _currentChannel;

  // 当前选中的视频源索引
  int _sourceIndex = 0;

  // 视频播放器控制器
  VideoPlayerController? _playerController;

  // 是否处于缓冲状态
  bool isBuffering = false;

  // 是否正在播放
  bool isPlaying = false;

  // 视频的宽高比
  double aspectRatio = 1.78;

  // 标记侧边抽屉（频道选择）是否打开
  bool _drawerIsOpen = false;

  // 重试次数计数器
  int _retryCount = 0;

  // 最大重试次数
  final int maxRetries = defaultMaxRetries;

  // 等待超时检测
  bool _timeoutActive = false;

  // 是否处于释放状态
  bool _isDisposing = false;

  // 切换时的竞态条件
  bool _isSwitchingChannel = false;

  // 超时检测时间
  final int timeoutSeconds = defaultTimeoutSeconds;

  // 标记是否需要更新宽高比
  bool _shouldUpdateAspectRatio = true;

  // 声明变量，存储 StreamUrl 类的实例
  StreamUrl? _streamUrl;

  // 收藏列表相关
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  
  // 抽屉刷新键
  ValueKey<int>? _drawerRefreshKey;

  // 实例化 TrafficAnalytics 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();

  // 音频检测状态
  bool _isAudio = false;

  // 检查是否为音频流
  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }
  
/// 播放前解析频道的视频源 
Future<void> _playVideo() async {
    if (_currentChannel == null) return;
    
    setState(() {
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
        _isRetrying = false;  // 播放开始时重置重试状态
    });
    
    try {
        // 解析URL
        String url = _currentChannel!.urls![_sourceIndex].toString();
        
        _streamUrl = StreamUrl(url);
        String parsedUrl = await _streamUrl!.getStreamUrl();
        
        if (parsedUrl == 'ERROR') {  // 如果解析返回错误就不需要重试
            setState(() {
                toastString = S.current.vpnplayError;
                _retryCount = 0;  // 重置重试计数，这样新的源可以重试
            });
            _handleSourceSwitch();
            return;
        }

        // 检查是否为音频URL
        bool isDirectAudio = _checkIsAudioStream(parsedUrl);
        setState(() {
          _isAudio = isDirectAudio;
        });
      
        LogUtil.i('准备播放：$parsedUrl');

        // 准备 HTTP 头
        final headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        };

        VideoPlayerController newController;
      
        bool isSeparatedStream = false;  // 声明并初始化变量

        // 检查是否为 YouTube 分离流并处理
        if (_streamUrl?.isYTUrl(parsedUrl) == true) {
            isSeparatedStream = await _separatedStreamHandler.isSeparatedStream(parsedUrl);
        }
        
        // 启动超时检测
        _startTimeoutCheck();
        
        if (isSeparatedStream) {
            // 使用分离流处理器初始化
            newController = await _separatedStreamHandler.initialize(parsedUrl, headers);
        } else {
            // 创建普通播放器控制器
            newController = VideoPlayerController.networkUrl(
                Uri.parse(parsedUrl),
                httpHeaders: headers,
                formatHint: parsedUrl.endsWith('.m3u8') ? VideoFormat.hls : null,  // 根据文件类型设置格式
                videoPlayerOptions: VideoPlayerOptions(
                    allowBackgroundPlayback: false,
                    mixWithOthers: false,
                    webOptions: const VideoPlayerWebOptions(
                        controls: VideoPlayerWebOptionsControls.enabled(),
                    ),
                ),
            )..setVolume(1.0);

            // 等待初始化完成
            try {
                await newController.initialize();
            } catch (e, stackTrace) {
                await newController.dispose();
                setState(() {
                    _retryCount = 0;
                });
                _handleSourceSwitch();
                LogUtil.logError('初始化出错', e, stackTrace);
                throw e;
            }
        }

        // 确保状态正确后再设置控制器
        if (!mounted || _isDisposing) {
            await newController.dispose();
            return;
        }

        // 先释放旧播放器，再设置新播放器
        await _disposePlayer();

        // 设置新的控制器
        setState(() {
            _playerController = newController;
            toastString = S.current.loading;
            _retryCount = 0;
            _timeoutActive = false;
        });
      
        // 添加监听并开始播放
        _playerController?.addListener(_videoListener);
        await _playerController?.play();
   
    } catch (e, stackTrace) {
        LogUtil.logError('播放出错', e, stackTrace);
        setState(() {
            _isRetrying = false;
            _retryCount = 0;
        });
        _handleSourceSwitch();
    }
}

/// 播放器监听方法
void _videoListener() {
    if (_playerController == null || _isDisposing || _isRetrying) return;

    if (_playerController!.value.hasError) {
        LogUtil.logError('播放器错误', _playerController!.value.errorDescription);
        return;
    }

    if (mounted) {  // 确保 widget 还在树中
        setState(() {
            // 更新缓冲状态
            isBuffering = _playerController!.value.isBuffering;
            
            // 更新播放状态和宽高比
            if (isPlaying != _playerController!.value.isPlaying) {
                isPlaying = _playerController!.value.isPlaying;
                if (isPlaying && _shouldUpdateAspectRatio) {
                    aspectRatio = _playerController?.value.aspectRatio ?? 1.78;
                    _shouldUpdateAspectRatio = false;
                }
            }
        });
    }
}

/// 超时检测方法
void _startTimeoutCheck() {
    if (_timeoutActive || _isRetrying) return;
    
    _timeoutActive = true;
    Timer(Duration(seconds: timeoutSeconds), () {
      if (!_timeoutActive || _isRetrying) return;
      
      if (_playerController != null && 
          !_playerController!.value.isPlaying && 
          !isBuffering) {  // 考虑缓冲状态
        LogUtil.logError('播放超时', 'Timeout after $timeoutSeconds seconds');
        _retryPlayback();
      }
    });
}

/// 重试播放方法
void _retryPlayback() {
    if (_isRetrying) return;
    
    _isRetrying = true;
    _timeoutActive = false;
    _retryCount += 1;

    if (_retryCount <= maxRetries) {
        setState(() {
            toastString = S.current.retryplay;
        });
        
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 3), () {
            setState(() {
               _isRetrying = false;  // 重试前重置状态
            });
            _playVideo();
        });
    } else {
        setState(() {
            _retryCount = 0;  // 重置重试计数，这样新的源可以重试
            _isRetrying = false;  // 重置重试状态
        });
        _handleSourceSwitch();
    }
}

/// 处理视频源切换的方法
void _handleSourceSwitch() {
    // 获取当前频道的视频源列表
    final List<String>? urls = _currentChannel?.urls;
    if (urls == null || urls.isEmpty) {
        setState(() {
            toastString = S.current.playError;
            _isRetrying = false;
            _retryCount = 0;
        });
        return;
    }

    // 切换到下一个源
    _sourceIndex += 1;
    if (_sourceIndex >= urls.length) {
        setState(() {
            toastString = S.current.playError;
            _isRetrying = false;  
            _retryCount = 0;
            _sourceIndex = 0;
        });
        return;
    }

    // 检查新的源是否为音频
    bool isDirectAudio = _checkIsAudioStream(urls[_sourceIndex]);
    setState(() {
        _isAudio = isDirectAudio;
        toastString = S.current.switchLine(_sourceIndex + 1);
    });

    // 延迟后尝试新源
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
        setState(() {
            _retryCount = 0;  // 新源从0开始计数重试
            _isRetrying = false;  
        });
        _playVideo();
    });
}

/// 播放器资源释放方法 - 修改以支持分离流
Future<void> _disposePlayer() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    final currentController = _playerController;
    
    try {
        if (currentController != null) {
            // 先移除监听器避免回调
            currentController.removeListener(_videoListener);
            _timeoutActive = false;
            _retryTimer?.cancel();
            
            // 尝试暂停播放
            if (currentController.value.isPlaying) {
                try {
                    await currentController.pause();
                } catch (e) {
                    LogUtil.logError('暂停播放时出错', e);
                }
            }
            
            // 清理 StreamUrl
            _disposeStreamUrl();
            
            // 清理分离流处理器
            await _separatedStreamHandler.dispose();
            
            // 释放播放器
            try {
                await currentController.dispose();
            } catch (e) {
                LogUtil.logError('释放播放器时出错', e);
            }
            
            // 只有在确保释放完成后才置空控制器
            if (_playerController == currentController) {
                _playerController = null;
            }
        }
    } catch (e, stackTrace) {
        LogUtil.logError('释放播放器资源时出错', e, stackTrace);
    } finally {
        _isDisposing = false;
    }
}

/// 释放 StreamUrl 实例
void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _streamUrl!.dispose();
      _streamUrl = null;
    }
}

/// 处理频道切换操作
Future<void> _onTapChannel(PlayModel? model) async {
    if (_isSwitchingChannel || model == null) return;
    
    setState(() {
        _isSwitchingChannel = true;
        toastString = S.current.loading; // 更新加载状态
    });
    
    try {
        // 先停止当前播放和清理状态
        await _disposePlayer();  // 确保先释放当前播放器资源
        _retryTimer?.cancel();
        setState(() { 
            _isRetrying = false;
            _timeoutActive = false;
        });
        
        // 更新频道信息
        _currentChannel = model;
        _sourceIndex = 0;
        _retryCount = 0;
        _shouldUpdateAspectRatio = true;

        // 检查新频道是否为音频
        final String? url = model.urls?.isNotEmpty == true ? model.urls![0] : null;
        bool isDirectAudio = _checkIsAudioStream(url);
        setState(() {
          _isAudio = isDirectAudio;
        });

        // 发送统计数据
        if (Config.Analytics) {
            await _sendTrafficAnalytics(context, _currentChannel!.title);
        }

        // 确保状态正确后开始新的播放
        if (!_isSwitchingChannel) return; // 如果状态已改变则退出
        await _playVideo();
        
    } catch (e, stackTrace) {
        LogUtil.logError('切换频道失败', e, stackTrace);
        setState(() {
            toastString = S.current.playError;
        });
    } finally {
        if (mounted) { // 确保 widget 还在树中
            setState(() {
                _isSwitchingChannel = false;
            });
        }
    }
}

/// 发送页面访问统计数据
Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: channelName);
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
      }
    }
}

/// 异步加载视频数据
Future<void> _loadData() async {
    // 重置所有状态
    _retryTimer?.cancel();
    setState(() { 
        _isRetrying = false;
        _timeoutActive = false;
        _retryCount = 0;
        _isAudio = false; // 重置音频状态
    });
    
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载数据时出错', e, stackTrace);
      await _parseData();
    }
}

/// 解析并加载本地播放列表
Future<void> _parseData() async {
    try {
      final resMap = await M3uUtil.getLocalM3uData();
      _videoMap = resMap.data;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('解析播放列表时出错', e, stackTrace);
    }
}

/// 处理播放列表
Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        final String? url = _currentChannel?.urls?.isNotEmpty == true ? _currentChannel?.urls![0] : null;
        bool isDirectAudio = _checkIsAudioStream(url);
        setState(() {
          _isAudio = isDirectAudio;
        });

        if (Config.Analytics) {
          await _sendTrafficAnalytics(context, _currentChannel!.title);
        }
        
        setState(() {
          _retryCount = 0;
          _timeoutActive = false;
          _playVideo(); 
        });
      } else {
        setState(() {
          toastString = 'UNKNOWN';
          _isRetrying = false;
        });
      }
    } else {
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN';
        _isRetrying = false;
      });
    }
}

/// 从播放列表中动态提取频道
PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    for (String category in playList.keys) {
      if (playList[category] is Map<String, Map<String, PlayModel>>) {
        Map<String, Map<String, PlayModel>> groupMap = playList[category];

        for (String group in groupMap.keys) {
          Map<String, PlayModel> channelMap = groupMap[group] ?? {};
          for (PlayModel? channel in channelMap.values) {
            if (channel?.urls != null && channel!.urls!.isNotEmpty) {
              return channel;
            }
          }
        }
      } else if (playList[category] is Map<String, PlayModel>) {
        Map<String, PlayModel> channelMap = playList[category] ?? {};
        for (PlayModel? channel in channelMap.values) {
          if (channel?.urls != null && channel!.urls!.isNotEmpty) {
            return channel;
          }
        }
      }
    }
    return null;
}

/// 切换视频源方法
Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    _retryTimer?.cancel();
    _isRetrying = false;
    _timeoutActive = false;

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      bool isDirectAudio = _checkIsAudioStream(sources[selectedIndex]);
      setState(() {
        _isAudio = isDirectAudio;
      });
      _retryCount = 0;
      _playVideo();
    }
}

/// 日志记录增强方法
void _logRetryEvent(String event, [dynamic error, StackTrace? stackTrace]) {
    final channelInfo = '频道: ${_currentChannel?.title ?? 'unknown'}, 源索引: $_sourceIndex';
    final retryInfo = '重试次数: $_retryCount, 是否重试中: $_isRetrying';
    final message = '$event\n$channelInfo\n$retryInfo';
    
    if (error != null) {
      LogUtil.logError(message, error, stackTrace);
    } else {
      LogUtil.i(message);
    }
}

/// 检查播放状态的辅助方法
bool _isPlaybackHealthy() {
    if (_playerController == null) return false;
    
    return _playerController!.value.isPlaying && 
           !_playerController!.value.hasError &&
           !isBuffering;
}

/// 处理返回按键逻辑
Future<bool> _handleBackPress(BuildContext context) async {
  if (_drawerIsOpen) {
    setState(() {
      _drawerIsOpen = false;
    });
    return false;
  }

  bool wasPlaying = _playerController?.value.isPlaying ?? false;
  if (wasPlaying) {
    await _playerController?.pause();
  }

  bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
  
  if (!shouldExit && wasPlaying && mounted) {
    await _playerController?.play();
  }
  
  return shouldExit;
}

/// 收藏列表相关方法
void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
       favoriteList = {
          Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!
       };
    } else {
       favoriteList = {
          Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
       };
    }
}

// 以下各种获取方法保持不变
String getGroupName(String channelId) {
    return _currentChannel?.group ?? '';
}

String getChannelName(String channelId) {
    return _currentChannel?.title ?? '';
}

List<String> getPlayUrls(String channelId) {
    return _currentChannel?.urls ?? [];
}

bool isChannelFavorite(String channelId) {
    String groupName = getGroupName(channelId);
    String channelName = getChannelName(channelId);
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
}

// 添加或取消收藏方法保持不变
void toggleFavorite(String channelId) async {
    // ... 保持原有实现不变 ...
}

/// 初始化方法 - 修改以初始化分离流处理器
@override
void initState() {
    super.initState();

    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    _loadData();
    _extractFavoriteList();

    Future.delayed(Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
}

/// 清理所有资源 - 修改以清理分离流处理器
@override
void dispose() {
    _retryTimer?.cancel();
    _timeoutActive = false;
    _isRetrying = false;
    WakelockPlus.disable();
    _isDisposing = true;
    _disposePlayer();
    // 确保分离流处理器被清理
    _separatedStreamHandler.dispose();
    super.dispose();
}

/// 播放器公共属性
Map<String, dynamic> _buildCommonProps() {
    return {
      'videoMap': _videoMap,
      'playModel': _currentChannel,
      'onTapChannel': _onTapChannel,
      'toastString': toastString,
      'controller': _playerController,
      'isBuffering': isBuffering,
      'isPlaying': isPlaying,
      'aspectRatio': aspectRatio,
      'onChangeSubSource': _parseData,
      'changeChannelSources': _changeChannelSources,
    };
}

@override
Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;

    if (isTV) {
      return TvPage(
        videoMap: _videoMap,
        playModel: _currentChannel,
        onTapChannel: _onTapChannel,
        toastString: toastString,
        controller: _playerController,
        isBuffering: isBuffering,
        isPlaying: isPlaying,
        aspectRatio: aspectRatio,
        onChangeSubSource: _parseData,
        changeChannelSources: _changeChannelSources,
        toggleFavorite: toggleFavorite,
        isChannelFavorite: isChannelFavorite,
        currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
        isAudio: _isAudio,
      );
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: MobileVideoWidget(
              toastString: toastString,
              controller: _playerController,
              changeChannelSources: _changeChannelSources,
              isLandscape: false,
              isBuffering: isBuffering,
              isPlaying: isPlaying,
              aspectRatio: aspectRatio,
              onChangeSubSource: _parseData,
              drawChild: ChannelDrawerPage(
                key: _drawerRefreshKey,
                refreshKey: _drawerRefreshKey,
                videoMap: _videoMap,
                playModel: _currentChannel,
                onTapChannel: _onTapChannel,
                isLandscape: false,
                onCloseDrawer: () {
                  setState(() {
                    _drawerIsOpen = false;
                  });
                },
              ),
              toggleFavorite: toggleFavorite,
              currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
              isChannelFavorite: isChannelFavorite,
              isAudio: _isAudio,
            ),
          );
        },
        landscape: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: Stack(
              children: [
                Scaffold(
                  body: toastString == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _parseData)
                      : TableVideoWidget(
                          toastString: toastString,
                          controller: _playerController,
                          isBuffering: isBuffering,
                          isPlaying: isPlaying,
                          aspectRatio: aspectRatio,
                          drawerIsOpen: _drawerIsOpen,
                          changeChannelSources: _changeChannelSources,
                          isChannelFavorite: isChannelFavorite,
                          currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                          toggleFavorite: toggleFavorite,
                          isLandscape: true,
                          isAudio: _isAudio,
                          onToggleDrawer: () {
                            setState(() {
                              _drawerIsOpen = !_drawerIsOpen;
                            });
                          },
                        ),
                ),
                Offstage(
                  offstage: !_drawerIsOpen,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _drawerIsOpen = false;
                      });
                    },
                    child: ChannelDrawerPage(
                      key: _drawerRefreshKey,
                      refreshKey: _drawerRefreshKey,
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () {  
                        setState(() {
                          _drawerIsOpen = false;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
