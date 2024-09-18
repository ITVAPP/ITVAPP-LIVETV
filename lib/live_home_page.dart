import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; 
import 'provider/theme_provider.dart'; 
import 'package:responsive_builder/responsive_builder.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'channel_drawer_page.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'mobile_video_widget.dart';
import 'table_video_widget.dart';
import 'tv/tv_page.dart';
import 'util/env_util.dart';
import 'util/check_version_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'widget/empty_page.dart';

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; 

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1;
  static const int defaultTimeoutSeconds = 12;

  String toastString = S.current.loading;
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  VideoPlayerController? _playerController;
  bool isBuffering = false;
  bool isPlaying = false;
  double aspectRatio = 1.78;
  bool _drawerIsOpen = false;
  bool isDebugMode = false;
  int _retryCount = 0;
  final int maxRetries = defaultMaxRetries;
  bool _timeoutActive = false;
  bool _isDisposing = false;
  bool _isSwitchingChannel = false;
  final int timeoutSeconds = defaultTimeoutSeconds;
  StreamUrl? _streamUrl;

  /// 重置播放状态的方法
  void _resetPlaybackState() {
    _retryCount = 0;   // 重置重试次数
    _sourceIndex = 0;  // 重置视频源索引
    _timeoutActive = false;  // 取消超时检测状态
    isBuffering = false;  // 重置缓冲状态
    isPlaying = false;    // 重置播放状态
  }


  /// 统一处理播放列表和EPG逻辑的方法
  void _handlePlaylistAndEPG({required void Function() onEmpty}) {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      setState(() {
        _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
        _playVideo();
      });

      _loadEPGData();
    } else {
      onEmpty();
    }
  }
  
  /// 加载EPG数据的通用方法
  void _loadEPGData() {
    if (_videoMap?.epgUrl != null && _videoMap?.epgUrl != '') {
      EpgUtil.loadEPGXML(_videoMap!.epgUrl!);
    } else {
      EpgUtil.resetEPGXML();
    }
  }

  /// 播放视频的核心方法
  Future<void> _playVideo() async {
    if (_currentChannel == null || _isSwitchingChannel || _isDisposing) return;

    _isSwitchingChannel = true;

    // 释放旧的资源
    await _disposeResources();

    // 更新加载提示
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

    // 获取视频URL
    String url = _currentChannel!.urls![_sourceIndex].toString();
    _streamUrl = StreamUrl(url);

    try {
      url = await _getParsedStreamUrl(url);
      await _initializeAndPlayVideo(url);
    } catch (e, stackTrace) {
      LogUtil.logError('解析视频地址出错', e, stackTrace);
      setState(() {
        toastString = S.current.playError;
      });
      _isSwitchingChannel = false;
    }
  }

  /// 解析StreamUrl
  Future<String> _getParsedStreamUrl(String url) async {
    String parsedUrl = await _streamUrl!.getStreamUrl();
    if (parsedUrl == 'ERROR') {
      throw Exception('解析视频地址出错');
    }

    if (isDebugMode) {
      bool shouldPlay = await _showConfirmationDialog(context, parsedUrl);
      if (!shouldPlay) {
        throw Exception('用户取消播放');
      }
    }
    return parsedUrl;
  }

  /// 初始化并播放视频
  Future<void> _initializeAndPlayVideo(String url) async {
    try {
      _playerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
          mixWithOthers: false,
          webOptions: const VideoPlayerWebOptions(controls: VideoPlayerWebOptionsControls.enabled()),
        ),
      )..setVolume(1.0);

      await _playerController?.initialize();
      _playerController?.play();
      setState(() {
        toastString = S.current.loading; 
      });

      _resetPlaybackState();
      _startTimeoutCheck();
    } catch (e, stackTrace) {
      LogUtil.logError('播放出错', e, stackTrace);
      _retryPlayback();
    } finally {
      _isSwitchingChannel = false;
    }
  }

  /// 统一资源释放方法
  Future<void> _disposeResources() async {
    if (_streamUrl != null) {
      _streamUrl!.dispose();
      _streamUrl = null;
    }

    if (_playerController != null && !_isDisposing) {
      _isDisposing = true;
      try {
        await _disposePlayerController();
      } catch (e, stackTrace) {
        LogUtil.logError('释放播放器资源时出错', e, stackTrace);
      } finally {
        _playerController = null; 
        _isDisposing = false;
      }
    }
  }

  /// 释放播放器控制器
  Future<void> _disposePlayerController() async {
    if (_playerController!.value.isPlaying) {
      await _playerController!.pause();
    }
    _timeoutActive = false;
    _playerController!.removeListener(_videoListener);
    await _playerController!.dispose();
  }

  /// 超时检测
  void _startTimeoutCheck() {
    _timeoutActive = true;
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (_shouldAbortTimeout()) return;
      _retryPlayback();
    });
  }

  /// 判断是否需要终止超时检测
  bool _shouldAbortTimeout() {
    return _isDisposing || (_timeoutActive && _playerController != null && !_playerController!.value.isPlaying);
  }

  /// 处理播放失败的逻辑
  void _retryPlayback() {
    _timeoutActive = false;
    _retryCount += 1;
    _disposeResources();

    if (_retryCount <= maxRetries) {
      _showRetryToast();
      _retryAfterDelay();
    } else {
      _switchToNextSource();
    }
  }

  /// 显示重试提示
  void _showRetryToast() {
    setState(() {
      toastString = '正在重试播放 ($_retryCount / $maxRetries)...';
    });
  }

  /// 延迟重试播放
  void _retryAfterDelay() {
    Future.delayed(const Duration(seconds: 2), () {
      if (_isDisposing) return;
      _playVideo();
    });
  }

  /// 切换到下一个视频源
  void _switchToNextSource() {
    _sourceIndex += 1;
    if (_sourceIndex > _currentChannel!.urls!.length - 1) {
      _handleLastSourceError();
    } else {
      _switchSourceAfterDelay();
    }
  }

  /// 处理最后一个源的错误
  void _handleLastSourceError() {
    _sourceIndex = _currentChannel!.urls!.length - 1;
    setState(() {
      toastString = S.current.playError;
    });
  }

  /// 延迟切换源
  void _switchSourceAfterDelay() {
    setState(() {
      toastString = S.current.switchLine(_sourceIndex + 1);
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (_isDisposing) return;
      _playVideo();
    });
  }

  /// 播放确认对话框
  Future<bool> _showConfirmationDialog(BuildContext context, String url) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(S.of(context).foundStreamTitle),
              content: Text(S.of(context).streamUrlContent(url)),
              actions: <Widget>[
                TextButton(
                  child: Text(S.of(context).cancelButton),
                  onPressed: () {
                    Navigator.of(context).pop(false); 
                  },
                ),
                TextButton(
                  child: Text(S.of(context).playButton),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false; 
  }

  /// 监听视频播放状态
  void _videoListener() {
    if (_playerController == null || _isDisposing) return;

    if (_playerController!.value.hasError) {
      _disposeResources(); 
      _retryPlayback();
      return;
    }

    _updatePlayerState();
  }

  /// 更新播放器状态
  void _updatePlayerState() {
    setState(() {
      isBuffering = _playerController!.value.isBuffering;
      isPlaying = _playerController!.value.isPlaying;

      if (isPlaying) {
        aspectRatio = _playerController?.value.aspectRatio ?? 1.78;
        _timeoutActive = false;
      }
    });
  }

  /// 处理频道切换
  Future<void> _onTapChannel(PlayModel? model) async {
    _timeoutActive = false;
    _currentChannel = model;
    _sourceIndex = 0;
    _retryCount = 0;
    _playVideo();
  }

  @override
  void initState() {
    super.initState();

    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    _loadData();
  }

  /// 从播放列表中动态提取频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    String category = playList.keys.first;
    if (playList[category] is Map<String, Map<String, PlayModel>>) {
      String group = (playList[category] as Map<String, Map<String, PlayModel>>).keys.first;
      String channel = (playList[category] as Map<String, Map<String, PlayModel>>)[group]!.keys.first;
      return (playList[category] as Map<String, Map<String, PlayModel>>)[group]![channel];
    } else if (playList[category] is Map<String, PlayModel>) {
      String channel = (playList[category] as Map<String, PlayModel>).keys.first;
      return (playList[category] as Map<String, PlayModel>)[channel];
    }
    return null;
  }

  /// 异步加载视频数据和版本检测
  _loadData() async {
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;

      _handlePlaylistAndEPG(onEmpty: () {
        setState(() {
          _currentChannel = null;
          _disposeResources();
          toastString = 'UNKNOWN';
        });
      });

      CheckVersionUtil.checkVersion(context, false, false);
    } catch (e, stackTrace) {
      LogUtil.logError('加载数据时出错', e, stackTrace);
      await _parseData();
    }
  }

  /// 解析本地播放列表数据
  Future<void> _parseData() async {
    try {
      final resMap = await M3uUtil.getLocalM3uData();
      _videoMap = resMap.data;
      _sourceIndex = 0;

      _handlePlaylistAndEPG(onEmpty: () {
        setState(() {
          _currentChannel = null;
          _disposeResources();
          toastString = 'UNKNOWN';
        });
      });
    } catch (e, stackTrace) {
      LogUtil.logError('解析播放列表时出错', e, stackTrace);
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _isDisposing = true;
    _disposeResources();
    super.dispose();
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
      );
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return MobileVideoWidget(
            toastString: toastString,
            controller: _playerController,
            changeChannelSources: _changeChannelSources,
            isLandscape: false,
            isBuffering: isBuffering,
            isPlaying: isPlaying,
            aspectRatio: aspectRatio,
            onChangeSubSource: _parseData,
            drawChild: ChannelDrawerPage(
              videoMap: _videoMap,
              playModel: _currentChannel,
              onTapChannel: _onTapChannel,
              isLandscape: false,
            ),
          );
        },
        landscape: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (!didPop) {
                SystemChrome.setPreferredOrientations(
                    [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
              }
            },
            child: Scaffold(
              drawer: ChannelDrawerPage(videoMap: _videoMap, playModel: _currentChannel, onTapChannel: _onTapChannel, isLandscape: true),
              drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.3,
              drawerScrimColor: Colors.transparent,
              onDrawerChanged: (bool isOpened) {
                setState(() {
                  _drawerIsOpen = isOpened;
                });
              },
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
                      isLandscape: true),
            ),
          );
        },
      ),
    );
  }

  /// 切换视频源的方法
  Future<void> _changeChannelSources() async {
    List<String> sources = _videoMap!.playList![_currentChannel!.group]![_currentChannel!.title]!.urls!;
    final selectedIndex = await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.black87,
        builder: (BuildContext context) {
          return SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 40),
              color: Colors.transparent,
              child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(sources.length, (index) {
                    return OutlinedButton(
                        autofocus: _sourceIndex == index,
                        style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: BorderSide(color: _sourceIndex == index ? Colors.red : Colors.white),
                            foregroundColor: Colors.redAccent),
                        onPressed: _sourceIndex == index
                            ? null
                            : () {
                                Navigator.pop(context, index);
                              },
                        child: Text(
                          S.current.lineIndex(index + 1),
                          style: TextStyle(fontSize: 12, color: _sourceIndex == index ? Colors.red : Colors.white),
                        ));
                  })),
            ),
          );
        });

    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      _playVideo();
    }
  }
}
