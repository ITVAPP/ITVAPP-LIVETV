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
import 'util/dialog_util.dart';
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
  static const int defaultTimeoutSeconds = 8;

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

  StreamUrl? _streamUrl; 

  /// 每次播放新视频前，解析当前频道的视频源，并进行播放。
Future<void> _playVideo() async {
  	
LogUtil.i('触发播放前检查频道：$_currentChannel');
LogUtil.i('触发播放前检查竞态条件：$_isSwitchingChannel');
LogUtil.i('触发播放前检查资源释放：$_isDisposing');

    if (_currentChannel == null || _isSwitchingChannel || _isDisposing) return;

    // 在开始播放之前，释放旧的资源
    await _disposePlayer();
    
    _isSwitchingChannel = true;

    // 更新界面上的加载提示文字
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

    // 获取当前视频源的 URL
    String url = _currentChannel!.urls![_sourceIndex].toString();

    // 使用 StreamUrl 类解析并处理一些特定的视频源
    _streamUrl = StreamUrl(url);
    try {
      // 获取解析后的有效视频 URL
      String parsedUrl = await _streamUrl!.getStreamUrl();

      // 如果解析失败，返回 'ERROR'，则显示错误信息并终止播放
      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.playError;
        });
        return;
      }

      // 如果解析成功，使用解析后的 URL
      url = parsedUrl;

      // 如果处于调试模式，则弹出确认对话框
      if (isDebugMode) {
        bool shouldPlay = await _showConfirmationDialog(context, url);
        if (!shouldPlay) {
          return; 
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('解析视频地址出错', e, stackTrace);
      setState(() {
        toastString = S.current.playError;
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
      await _playerController?.initialize();
      _playerController?.play();
      setState(() {
        toastString = S.current.loading; // 更新 UI，显示加载状态
      });

      // 播放成功，重置重试次数计数器
      _retryCount = 0;
      _timeoutActive = false; // 播放成功，取消超时检测
      _playerController?.addListener(_videoListener); 

      // 添加超时检测机制
      _startTimeoutCheck();
    } catch (e, stackTrace) {
      LogUtil.logError('播放出错', e, stackTrace);
      _retryPlayback(); // 调用处理方法
    } finally {
      _isSwitchingChannel = false; 
    }
  }

  /// 播放器资源释放
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
        LogUtil.logError('释放播放器资源时出错', e, stackTrace); 
      } finally {
        _playerController = null; // 确保播放器控制器置空
        _isDisposing = false;
      }
    }
  }

  /// 释放 StreamUrl 实例
  void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _streamUrl!.dispose(); 
      _streamUrl = null;   
    }
  }

  /// 超时检测，超时后未播放则自动重试
  void _startTimeoutCheck() {
    _timeoutActive = true;
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (_isDisposing) return;
      if (_timeoutActive && _playerController != null && !_playerController!.value.isPlaying) {
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
        if (_isDisposing) return;
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
          if (_isDisposing) return; 
          _playVideo();
        });
      }
    }
  }

  /// 显示播放确认对话框
Future<bool> _showConfirmationDialog(BuildContext context, String url) async {
  return await DialogUtil.showCustomDialog(
    context,
    title: S.of(context).foundStreamTitle,  // 动态传入标题
    content: S.of(context).streamUrlContent(url),  // 动态传入内容
    positiveButtonLabel: S.of(context).playButton,  // 正向按钮文本：播放
    onPositivePressed: () {
      Navigator.of(context).pop(true);  // 用户确认播放
    },
    negativeButtonLabel: S.of(context).cancelButton,  // 负向按钮文本：取消
    onNegativePressed: () {
      Navigator.of(context).pop(false);  // 用户取消播放
    },
    isDismissible: false,  // 禁止点击对话框外部关闭
  ) ?? false;  // 如果对话框意外关闭，返回 false
}

  /// 监听视频播放状态的变化
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
          aspectRatio = _playerController?.value.aspectRatio ?? 1.78;
        }
      });
    }
  }

  /// 处理频道切换操作
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
  // 遍历每个分类
  for (String category in playList.keys) {
    if (playList[category] is Map<String, Map<String, PlayModel>>) {
      // 三层结构处理
      Map<String, Map<String, PlayModel>> groupMap = playList[category];

      // 遍历每个组
      for (String group in groupMap.keys) {
        Map<String, PlayModel> channelMap = groupMap[group] ?? {};

        // 遍历每个频道，返回第一个有有效播放地址的频道
        for (PlayModel? channel in channelMap.values) {
          if (channel?.urls != null && channel!.urls!.isNotEmpty) {
            return channel;  // 找到第一个可用的频道，立即返回
          }
        }
      }
    } else if (playList[category] is Map<String, PlayModel>) {
      // 两层结构处理
      Map<String, PlayModel> channelMap = playList[category] ?? {};

      // 遍历每个频道，返回第一个有有效播放地址的频道
      for (PlayModel? channel in channelMap.values) {
        if (channel?.urls != null && channel!.urls!.isNotEmpty) {
          return channel;  // 找到第一个可用的频道，立即返回
        }
      }
    }
  }
  return null;  // 如果遍历所有频道都没有找到可用的，返回 null
}

  /// 异步加载视频数据和版本检测
  _loadData() async {
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist(); // 处理播放列表和 EPG 数据
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
    // 获取第一个可用的频道，如果该分类为空，跳过它
    _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

    if (_currentChannel != null) {
      // 确保不会重复调用播放方法
      if (!_isSwitchingChannel && !_isDisposing) {
        setState(() {
          _playVideo(); // 播放第一个可用的频道
        });
      }
    } else {
      // 没有可用的频道
      setState(() {
        toastString = 'UNKNOWN';
      });
    }

    // 处理 EPG 数据加载
    if (_videoMap?.epgUrl?.isNotEmpty ?? false) {
      try {
        EpgUtil.loadEPGXML(_videoMap!.epgUrl!); 
      } catch (e, stackTrace) {
        LogUtil.logError('加载EPG数据时出错', e, stackTrace); 
      }
    } else {
      EpgUtil.resetEPGXML(); // 重置EPG数据
    }
  } else {
    // 播放列表为空
    setState(() {
      _currentChannel = null; 
      toastString = 'UNKNOWN';
    });
  }
}

  @override
  void dispose() {
    // 禁用保持屏幕唤醒功能
    WakelockPlus.disable();
    _isDisposing = true; 
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
    bool isTV = context.watch<ThemeProvider>().isTV;

    // 电视设备加载不同的 UI 布局
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

  /// 通过底部弹出框选择不同的视频源
Future<void> _changeChannelSources() async {
  List<String>? sources = _currentChannel?.urls; 
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
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Wrap(
                spacing: 10,   
                runSpacing: 10, 
                children: List.generate(sources.length, (index) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 60), 
                    child: OutlinedButton(
                      autofocus: _sourceIndex == index,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6), 
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
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _sourceIndex == index ? Colors.white : Colors.black, 
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
    } 
  } catch (modalError, modalStackTrace) {
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
  }
}
}
