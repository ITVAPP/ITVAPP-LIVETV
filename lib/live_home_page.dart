import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // 导入Provider包
import 'provider/theme_provider.dart'; // 引入ThemeProvider
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
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

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

  StreamUrl? _streamUrl; // 用于存储当前的 StreamUrl 实例

  /// 播放视频的核心方法
  /// 每次播放新视频前，解析当前频道的视频源，并进行播放。
Future<void> _playVideo() async {
  	
LogUtil.e('触发播放前检查频道：$_currentChannel');
LogUtil.e('触发播放前检查竞态条件：$_isSwitchingChannel');
LogUtil.e('触发播放前检查资源释放：$_isDisposing');

    if (_currentChannel == null || _isSwitchingChannel || _isDisposing) return;

    // 在开始播放新视频之前，释放旧的资源
    await _disposePlayer();
    
    _isSwitchingChannel = true;

    // 更新界面上的加载提示文字，表明当前正在加载的流信息
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

    // 获取当前视频源的 URL
    String url = _currentChannel!.urls![_sourceIndex].toString();

    // 使用 StreamUrl 类解析并处理一些特定的视频源（例如 YouTube）
    _streamUrl = StreamUrl(url);
    try {
      // 获取解析后的有效视频 URL
      String parsedUrl = await _streamUrl!.getStreamUrl();

      // 如果解析失败，返回 'ERROR'，则显示错误信息并终止播放
      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.playError; // 更新 UI 显示播放错误提示
        });
        return;
      }

      // 如果解析成功，使用解析后的 URL
      url = parsedUrl;

      // 如果处于调试模式，则弹出确认对话框，允许用户确认是否播放该视频流
      if (isDebugMode) {
        bool shouldPlay = await _showConfirmationDialog(context, url);
        if (!shouldPlay) {
          return; 
        }
      }
    } catch (e, stackTrace) {
      // 如果解析视频流 URL 时发生异常，记录日志并显示错误提示
      LogUtil.logError('解析视频地址出错', e, stackTrace);
      setState(() {
        toastString = S.current.playError; // 显示错误提示
      });
      return;
    }

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
      });

      // 播放成功，重置重试次数计数器
      _retryCount = 0;
      _timeoutActive = false; // 播放成功，取消超时检测
      _playerController?.addListener(_videoListener); // 添加播放监听

      // 添加超时检测机制
      _startTimeoutCheck();
    } catch (e, stackTrace) {
      // 如果播放过程中发生异常，处理播放失败逻辑
      LogUtil.logError('播放出错', e, stackTrace);
      _retryPlayback(); // 调用处理方法
    } finally {
      _isSwitchingChannel = false; 
    }
  }

  /// 优化播放器资源释放
  Future<void> _disposePlayer() async {
    // 释放旧的 StreamUrl 实例
    _disposeStreamUrl();

    if (!_isDisposing) {
      _isDisposing = true;
      try {
        _timeoutActive = false; // 停止超时检测，避免后续重试
        _playerController?.removeListener(_videoListener); // 移除监听器
        await _playerController?.dispose(); // 释放资源
      } catch (e, stackTrace) {
        LogUtil.logError('释放播放器资源时出错', e, stackTrace); // 记录错误
      } finally {
        _playerController = null; // 确保播放器控制器置空
        _isDisposing = false;
      }
    }
  }

  /// 释放 StreamUrl 实例
  void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _streamUrl!.dispose();  // 调用 StreamUrl 的 dispose 方法释放资源
      _streamUrl = null;       // 释放后将其置空
    }
  }

  /// 超时检测，超时后未播放则自动重试
  void _startTimeoutCheck() {
    _timeoutActive = true; // 开始超时检测
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (_isDisposing) return; // 添加_isDisposing检查
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

    if (_retryCount <= maxRetries) {
      setState(() {
        toastString = '正在重试播放 ($_retryCount / $maxRetries)...';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (_isDisposing) return; // 添加_isDisposing检查
        _playVideo();
      });
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
        Future.delayed(const Duration(seconds: 2), () {
          if (_isDisposing) return; // 添加_isDisposing检查
          _playVideo();
        });
      }
    }
  }

  /// 显示播放确认对话框，用户可以选择是否播放当前视频流
  Future<bool> _showConfirmationDialog(BuildContext context, String url) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(S.of(context).foundStreamTitle),  //找到视频流
              content: Text(S.of(context).streamUrlContent(url)), // 你想播放这个流吗
              actions: <Widget>[
                TextButton(
                  child: Text(S.of(context).cancelButton),  //取消
                  onPressed: () {
                    Navigator.of(context).pop(false); // 用户取消播放
                  },
                ),
                TextButton(
                  child: Text(S.of(context).playButton),  //播放
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
    if (_playerController == null || _isDisposing) return;

    // 如果发生播放错误，则切换到下一个视频源
    if (_playerController!.value.hasError) {
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
        if (isPlaying) {
          aspectRatio = _playerController?.value.aspectRatio ?? 1.78; // 仅在开始播放时更新宽高比
        }
      });
    }
  }

  /// 处理频道切换操作
  /// 用户选择不同的频道时，重置视频源索引，并播放新频道的视频
  Future<void> _onTapChannel(PlayModel? model) async {
     _isSwitchingChannel = false; 
    _currentChannel = model;
    _sourceIndex = 0; // 重置视频源索引
    _retryCount = 0; // 重置重试次数计数器
    _timeoutActive = false; // 取消超时检测
    _playVideo(); // 开始播放选中的频道
  }

  @override
  void initState() {
    super.initState();

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 加载播放列表数据和版本检测
    _loadData();
  }

  /// 从播放列表中动态提取频道，处理两层和三层结构
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    String category = playList.keys.first;
    if (playList[category] is Map<String, Map<String, PlayModel>>) {
      // 三层结构处理
      String group = (playList[category] as Map<String, Map<String, PlayModel>>).keys.first;
      String channel = (playList[category] as Map<String, Map<String, PlayModel>>)[group]!.keys.first;
      return (playList[category] as Map<String, Map<String, PlayModel>>)[group]![channel];
    } else if (playList[category] is Map<String, PlayModel>) {
      // 两层结构处理
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

      await _handlePlaylist(); // 处理播放列表和 EPG 数据

      // 版本检测
      CheckVersionUtil.checkVersion(context, false, false);
    } catch (e, stackTrace) {
      LogUtil.logError('加载数据时出错', e, stackTrace);
      await _parseData();
    }
  }

  /// 解析并加载本地播放列表数据
  Future<void> _parseData() async {
    try {
      final resMap = await M3uUtil.getLocalM3uData(); // 获取播放列表数据
      _videoMap = resMap.data;
      _sourceIndex = 0;

      await _handlePlaylist(); // 处理播放列表和 EPG 数据
    } catch (e, stackTrace) {
      LogUtil.logError('解析播放列表时出错', e, stackTrace);
    }
  }

  /// 处理播放列表和 EPG 数据的通用逻辑
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      setState(() {
        _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
        _playVideo(); // 播放第一个频道
      });

      // 如果存在 EPG（节目预告）数据，则加载
      if (_videoMap?.epgUrl?.isNotEmpty ?? false) {
        EpgUtil.loadEPGXML(_videoMap!.epgUrl!);
      } else {
        EpgUtil.resetEPGXML(); // 如果没有 EPG 数据，重置
      }
    } else {
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN'; // 显示未知错误提示
      });
    }
  }

  @override
  void dispose() {
    // 禁用保持屏幕唤醒功能
    WakelockPlus.disable();

    _isDisposing = true; // 标记正在释放资源
    // 释放播放器和 StreamUrl 资源
    _disposePlayer(); 
    super.dispose();
  }

  /// 播放器参数公共属性
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
    // 使用 Provider 获取 isTV 值
    bool isTV = context.watch<ThemeProvider>().isTV;

    // 检测设备是否为电视设备，加载不同的 UI 布局
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
  List<String>? sources = _currentChannel?.urls;  // 直接从 currentChannel 获取视频源
  // 如果 sources 为空或不存在，记录日志
  if (sources == null || sources.isEmpty) {
    LogUtil.e('未找到有效的视频源');
    return;
  }

  try {
    // 显示选择线路的弹窗
    final selectedIndex = await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.black45,
      builder: (BuildContext context) {
        return SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20),
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7, // 限制最大宽度为屏幕宽度的70%
              ),
              child: Wrap(
                spacing: 5,   // 设置按钮之间的水平间距
                runSpacing: 10, // 设置按钮之间的垂直间距
                children: List.generate(sources.length, (index) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 60), // 设置最小宽度
                    child: OutlinedButton(
                      autofocus: _sourceIndex == index,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6),  // 设置按钮内边距为上下 8, 左右 16
                        backgroundColor: _sourceIndex == index ? Color(0xFFEB144C) : Colors.grey[300]!, 
                        side: BorderSide(color: _sourceIndex == index ? Color(0xFFEB144C) : Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), 
                        ),
                      ),
                      onPressed: _sourceIndex == index
                          ? null
                          : () {
                              Navigator.pop(context, index);
                            },
                      child: Text(
                        S.current.lineIndex(index + 1),
                        textAlign: TextAlign.center, // 确保文字居中
                        style: TextStyle(
                          fontSize: 14,
                          color: _sourceIndex == index ? Colors.white : Colors.black, // 选中和未选中状态的文字颜色
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );

    // 切换到选中的视频源并播放
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      _playVideo();
    } else {
      LogUtil.e('未选择新的视频源或选中的索引未发生变化');
    }
  } catch (modalError, modalStackTrace) {
    // 捕获弹窗异常并记录日志
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
  }
}
}
