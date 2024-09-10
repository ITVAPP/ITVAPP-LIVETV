import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
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
import 'util/check_version_util.dart';
import 'util/env_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'widget/empty_page.dart';

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  const LiveHomePage({super.key});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 超时重试次数
  static const int defaultMaxRetries = 1;
  // 超时检测的时间
  static const int defaultTimeoutSeconds = 12;

  // 存储加载状态的提示文字
  String toastString = S.current.loading;

  // 视频播放列表的数据模型，包含多个播放频道及其视频源
  PlaylistModel? _videoMap;

  // 当前播放的频道数据模型
  PlayModel? _currentChannel;

  // 当前选中的视频源索引，表示正在播放哪个线路的地址
  int _sourceIndex = 0;

  // 视频播放器控制器，用于控制视频的播放、暂停等操作
  VideoPlayerController? _playerController;

  // 标记播放器是否处于缓冲状态
  bool isBuffering = false;

  // 标记播放器是否正在播放
  bool isPlaying = false;

  // 视频的宽高比，用于调整视频显示比例
  double aspectRatio = 1.78;

  // 标记侧边抽屉（频道选择）是否打开
  bool _drawerIsOpen = false;

  // 调试模式开关，调试时为 true，生产环境为 false
  bool isDebugMode = false;

  // 重试次数计数器，记录当前播放重试的次数
  int _retryCount = 0;

  // 最大重试次数
  final int maxRetries = defaultMaxRetries;

  // 标志是否等待超时检测
  bool _timeoutActive = false;

  // 标志播放器是否处于释放状态
  bool _isDisposing = false;

  // 防止快速切换时的竞态条件
  bool _isSwitchingChannel = false;

  // 超时检测时间
  final int timeoutSeconds = defaultTimeoutSeconds;

  /// 播放视频的核心方法
  /// 每次播放新视频前，解析当前频道的视频源，并进行播放。
  Future<void> _playVideo() async {
    if (_currentChannel == null || _isSwitchingChannel) return;

    _isSwitchingChannel = true;

    // 更新界面上的加载提示文字，表明当前正在加载的流信息
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

    // 在开始播放新视频之前，释放旧的视频播放器资源
    await _disposePlayer();

    // 获取当前视频源的 URL
    String url = _currentChannel!.urls![_sourceIndex].toString();

    // 使用 StreamUrl 类解析并处理一些特定的视频源（例如 YouTube）
    StreamUrl streamUrl = StreamUrl(url);
    try {
      // 获取解析后的有效视频 URL
      String parsedUrl = await streamUrl.getStreamUrl();

      // 如果解析失败，返回 'ERROR'，则显示错误信息并终止播放
      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.playError; // 更新 UI 显示播放错误提示
        });
        _isSwitchingChannel = false;
        return;
      }

      // 如果解析成功，使用解析后的 URL
      url = parsedUrl;

      // 如果处于调试模式，则弹出确认对话框，允许用户确认是否播放该视频流
      if (isDebugMode) {
        bool shouldPlay = await _showConfirmationDialog(context, url);
        if (!shouldPlay) {
          _isSwitchingChannel = false;
          return; // 用户取消播放，退出函数
        }
      }
    } catch (e) {
      // 如果解析视频流 URL 时发生异常，记录日志并显示错误提示
      LogUtil.v('解析视频地址出错:::::$e');
      setState(() {
        toastString = S.current.playError; // 显示错误提示
      });
      _isSwitchingChannel = false;
      return;
    }

    LogUtil.v('正在播放:$_sourceIndex::${_currentChannel!.toJson()}');

    try {
      // 创建视频播放器控制器并初始化，使用解析后的 URL 播放视频
      _playerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
          mixWithOthers: false,
          webOptions: const VideoPlayerWebOptions(controls: VideoPlayerWebOptionsControls.enabled()),
        ),
      )..setVolume(1.0); // 设置音量

      // 初始化播放器，开始播放视频
      await _playerController?.initialize();
      _playerController?.play();
      setState(() {
        toastString = S.current.loading; // 更新 UI，显示加载状态
        aspectRatio = _playerController?.value.aspectRatio ?? 1.78; // 更新视频宽高比
      });

      // 播放成功，重置重试次数计数器
      _retryCount = 0;
      _timeoutActive = false; // 播放成功，取消超时检测
      _playerController?.addListener(_videoListener); // 添加播放监听

      // 添加超时检测机制
      _startTimeoutCheck();
    } catch (e) {
      // 如果播放过程中发生异常，处理播放失败逻辑
      LogUtil.v('播放出错:::::$e');
      _retryPlayback(); // 调用处理方法
    } finally {
      _isSwitchingChannel = false;
    }
  }

  /// 优化播放器资源释放
  Future<void> _disposePlayer() async {
    if (_playerController != null && !_isDisposing) {
      _isDisposing = true;
      if (_playerController!.value.isPlaying) {
        await _playerController!.pause(); // 确保视频暂停
      }
      _playerController!.removeListener(_videoListener); // 移除监听器
      await _playerController!.dispose(); // 释放资源
      _playerController = null;
      _isDisposing = false;
    }
  }

  /// 超时检测，超时后未播放则自动重试
  void _startTimeoutCheck() {
    _timeoutActive = true; // 开始超时检测
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (_timeoutActive && _playerController != null && !_playerController!.value.isPlaying) {
        LogUtil.v('超时未播放，自动重试');
        _retryPlayback();
      }
    });
  }

  /// 处理播放失败的逻辑，进行重试或切换线路
  void _retryPlayback() {
    _timeoutActive = false; // 处理失败，取消超时
    _retryCount += 1;
    
    // 在重试前释放播放器资源
    _disposePlayer(); // 确保释放旧的播放器资源

    if (_retryCount <= maxRetries) {
      setState(() {
        toastString = '正在重试播放 ($_retryCount / $maxRetries)...';
      });
      Future.delayed(const Duration(seconds: 2), () => _playVideo());
    } else {
      _sourceIndex += 1;
      if (_sourceIndex > _currentChannel!.urls!.length - 1) {
        _sourceIndex = _currentChannel!.urls!.length - 1;
        setState(() {
          toastString = S.current.playError;
        });
      } else {
        setState(() {
          toastString = S.current.switchLine(_sourceIndex + 1);
        });
        Future.delayed(const Duration(seconds: 2), () => _playVideo());
      }
    }
  }

  /// 显示播放确认对话框，用户可以选择是否播放当前视频流
  Future<bool> _showConfirmationDialog(BuildContext context, String url) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('找到视频流'),
              content: Text('流URL: $url\n\n你想播放这个流吗？'),
              actions: <Widget>[
                TextButton(
                  child: Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop(false); // 用户取消播放
                  },
                ),
                TextButton(
                  child: Text('播放'),
                  onPressed: () {
                    Navigator.of(context).pop(true); // 用户确认播放
                  },
                ),
              ],
            );
          },
        ) ??
        false; // 如果对话框意外关闭，返回 false
  }

  /// 监听视频播放状态的变化
  /// 包括检测缓冲状态、播放状态以及播放出错的情况
  void _videoListener() {
    if (_playerController == null) return;

    // 如果发生播放错误，则切换到下一个视频源
    if (_playerController!.value.hasError) {
      _disposePlayer(); // 确保在出错时释放播放器资源	
      _retryPlayback(); // 调用失败处理逻辑
      return;
    }

    // 更新缓冲状态
    if (isBuffering != _playerController!.value.isBuffering) {
      setState(() {
        isBuffering = _playerController!.value.isBuffering;
      });
    }

    // 更新播放状态
    if (isPlaying != _playerController!.value.isPlaying) {
      setState(() {
        isPlaying = _playerController!.value.isPlaying;
      });
    }

    // 如果播放器成功播放，取消超时检测
    if (_playerController!.value.isPlaying) {
      _timeoutActive = false; // 播放成功，取消超时
    }
  }

  /// 处理频道切换操作
  /// 用户选择不同的频道时，重置视频源索引，并播放新频道的视频
  Future<void> _onTapChannel(PlayModel? model) async {
    _timeoutActive = false; // 用户切换频道，取消之前的超时检测
    _currentChannel = model;
    _sourceIndex = 0; // 重置视频源索引
    LogUtil.v('onTapChannel:::::${_currentChannel?.toJson()}');
    
    await _disposePlayer(); // 确保之前的视频已停止并释放资源
    _playVideo(); // 开始播放选中的频道
  }

  @override
  void initState() {
    super.initState();

    // 初始化加载动画样式
    EasyLoading.instance
      ..loadingStyle = EasyLoadingStyle.custom
      ..indicatorColor = Colors.black
      ..textColor = Colors.black
      ..backgroundColor = Colors.white70;

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 加载播放列表数据和版本检测
    _loadData();
  }

  /// 异步加载视频数据和版本检测
  _loadData() async {
    await _parseData();
    CheckVersionUtil.checkVersion(context, false, false);
  }
  
  @override
  void dispose() {
    // 禁用保持屏幕唤醒功能
    WakelockPlus.disable();

    // 释放播放器资源
    _disposePlayer();
    super.dispose();
  }

  /// 解析并加载播放列表数据
  /// 从远程获取 M3U 播放列表并初始化当前播放的频道
  Future<void> _parseData() async {
    final resMap = await M3uUtil.getLocalM3uData(); // 获取播放列表数据
    LogUtil.v('_parseData:::::$resMap');
    _videoMap = resMap.data;
    _sourceIndex = 0;

    if (_videoMap?.playList?.isNotEmpty ?? false) {
      setState(() {
        // 加载第一个频道
        String group = _videoMap!.playList!.keys.first.toString();
        String channel = _videoMap!.playList![group]!.keys.first;
        _currentChannel = _videoMap!.playList![group]![channel];
        _playVideo(); // 播放第一个频道
      });

      // 如果存在 EPG（节目预告）数据，则加载
      if (_videoMap?.epgUrl != null && _videoMap?.epgUrl != '') {
        EpgUtil.loadEPGXML(_videoMap!.epgUrl!);
      } else {
        EpgUtil.resetEPGXML(); // 如果没有 EPG 数据，重置
      }
    } else {
      // 如果播放列表为空，显示未知错误提示
      setState(() {
        _currentChannel = null;
        _disposePlayer();
        toastString = 'UNKNOWN'; // 显示未知错误提示
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检测设备是否为电视设备，加载不同的 UI 布局
    if (EnvUtil.isTV()) {
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

    // 如果不是电视设备，加载移动设备布局
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
                  ? EmptyPage(onRefresh: _parseData) // 如果播放列表为空，显示错误页面
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

  /// 切换视频源的方法，通过底部弹出框选择不同的视频源
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

    // 切换到选中的视频源并开始播放
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      LogUtil.v('切换线路:====线路${_sourceIndex + 1}');
      _playVideo();
    }
  }
}
