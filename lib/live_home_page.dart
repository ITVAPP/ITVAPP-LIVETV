import 'dart:async';
import 'dart:convert';
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
  static const int defaultTimeoutSeconds = 18;

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
  
  // 调试模式开关，调试时为 true，生产环境为 false
  bool isDebugMode = false;

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

  // 实例化 TrafficAnalytics 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); 

  /// 播放前解析频道的视频源
  Future<void> _playVideo() async {
    // 更新界面上的加载提示文字
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

    LogUtil.i('检查竞态条件：$_isSwitchingChannel\n检查资源释放：$_isDisposing');
    if (_currentChannel == null || _isSwitchingChannel || _isDisposing) return;

    // 释放旧资源
    await _disposePlayer();

    _isSwitchingChannel = true;

    // 获取当前视频源的 URL
    String url = _currentChannel!.urls![_sourceIndex].toString();

    // 解析特定的视频源
    _streamUrl = StreamUrl(url);
    try {
      // 获取解析后的有效视频 URL
      String parsedUrl = await _streamUrl!.getStreamUrl();

      // 如果解析失败，返回 'ERROR'
      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.vpnplayError;
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
        toastString = S.current.vpnplayError;
      });
      return;
    }

    try {
      // 创建视频播放器控制器并初始化
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
        toastString = S.current.loading; // 显示加载状态
      });

      // 播放成功，重置重试计数器
      _retryCount = 0;
      _timeoutActive = false;
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

  /// 播放器资源释放
  Future<void> _disposePlayer() async {
    if (!_isDisposing) {
      _isDisposing = true;  // 标记为正在释放资源
      // 取消超时检测和重试逻辑
      _timeoutActive = false;
      // 移除与播放器相关的监听器
      _playerController?.removeListener(_videoListener);
      try {
        _disposeStreamUrl();  // 释放 StreamUrl 相关资源
        await _playerController?.dispose();  // 释放播放器资源
      } catch (e, stackTrace) {
        LogUtil.logError('释放播放器资源时出错', e, stackTrace);
      } finally {
        _playerController = null;
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

  /// 超时检测，超时自动重试
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
    _timeoutActive = false;
    _retryCount += 1;

    if (_retryCount <= maxRetries) {
      setState(() {
        toastString = S.current.retryplay;
      });
      Future.delayed(const Duration(seconds: 3), () {
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
        Future.delayed(const Duration(seconds: 3), () {
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
      title: S.current.foundStreamTitle,  // 传入标题
      content: S.current.streamUrlContent(url),  // 传入内容
      positiveButtonLabel: S.current.playButton,
      onPositivePressed: () {
        Navigator.of(context).pop(true);  // 确认播放
      },
      negativeButtonLabel: S.current.cancelButton,
      onNegativePressed: () {
        Navigator.of(context).pop(false);  // 取消播放
      },
      isDismissible: false,  // 禁止点击外部关闭
    ) ?? false;
  }

  /// 监听视频播放状态的变化
  void _videoListener() {
    if (_playerController == null || _isDisposing) return;

    // 如果发生播放错误，则切换到下一个视频源
    if (_playerController!.value.hasError) {
      _retryPlayback();
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
        if (isPlaying && _shouldUpdateAspectRatio)  {
          aspectRatio = _playerController?.value.aspectRatio ?? 1.78;
          _shouldUpdateAspectRatio = false;
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
    _shouldUpdateAspectRatio = true; // 重置宽高比标志位

    // 发送流量统计数据
    if (Config.Analytics) {
      await _sendTrafficAnalytics(context, _currentChannel!.title);
    }

    _playVideo(); 
  }

  @override
  void initState() {
    super.initState();

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 加载播放列表数据
    _loadData();

    // 加载收藏列表
    _extractFavoriteList();

    // 延迟1分钟后执行版本检测
    Future.delayed(Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
  }

  /// 从传递的播放列表中提取“我的收藏”部分
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
    LogUtil.i('初始化的收藏列表: ${favoriteList}');
  }

  // 获取当前频道的分组名字
  String getGroupName(String channelId) {
    return _currentChannel?.group ?? '';
  }

  // 获取当前频道名字
  String getChannelName(String channelId) {
    return _currentChannel?.title ?? '';
  }

  // 获取当前频道的播放地址列表
  List<String> getPlayUrls(String channelId) {
    return _currentChannel?.urls ?? [];
  }

  // 检查当前频道是否已收藏
  bool isChannelFavorite(String channelId) {
    String groupName = getGroupName(channelId);
    String channelName = getChannelName(channelId);
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  // 添加或取消收藏
  void toggleFavorite(String channelId) async {
    bool isFavoriteChanged = false;
    String actualChannelId = _currentChannel?.id ?? channelId;
    String groupName = getGroupName(actualChannelId);
    String channelName = getChannelName(actualChannelId);

    // 验证分组名字、频道名字和播放地址是否正确
    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(
        context,
        S.current.channelnofavorite,
        duration: Duration(seconds: 4),
      );
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      // 取消收藏
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(
        context,
        S.current.removefavorite,
        duration: Duration(seconds: 4),
      );
      isFavoriteChanged = true;
    } else {
      // 添加收藏
      if (favoriteList[Config.myFavoriteKey]![groupName] == null) {
        favoriteList[Config.myFavoriteKey]![groupName] = {};
      }

      PlayModel newFavorite = PlayModel(
        id: actualChannelId,
        group: groupName,
        logo: _currentChannel?.logo,
        title: channelName,
        urls: getPlayUrls(actualChannelId),
      );
      favoriteList[Config.myFavoriteKey]![groupName]![channelName] = newFavorite;
      CustomSnackBar.showSnackBar(
        context,
        S.current.newfavorite,
        duration: Duration(seconds: 4),
      );
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        // 保存收藏列表到缓存
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        LogUtil.i('保存后的收藏列表: ${favoriteList}');

        // 更新播放列表中的收藏部分
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];

        LogUtil.i('修改收藏列表后的播放列表: ${_videoMap}');
        // 保存更新后的播放列表到缓存
        await M3uUtil.saveCachedM3uData(_videoMap.toString());
        setState(() {}); // 重新渲染频道列表
      } catch (error) {
      CustomSnackBar.showSnackBar(
        context,
        S.current.newfavoriteerror,
        duration: Duration(seconds: 4),
      );
        LogUtil.logError('收藏状态保存失败', error);
      }
    }
  }

  /// 从播放列表中动态提取频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    for (String category in playList.keys) {
      if (playList[category] is Map<String, Map<String, PlayModel>>) {
        // 三层结构处理
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
        // 两层结构处理
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

  /// 异步加载视频数据
  _loadData() async {
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
      // 获取第一个可用的频道
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
      	
        // 发送流量统计数据
          if (Config.Analytics) {
          await _sendTrafficAnalytics(context, _currentChannel!.title);
        }
        
        if (!_isSwitchingChannel && !_isDisposing) {
          setState(() {
            _playVideo();
          });
        }
      } else {
        // 没有可用的频道
        setState(() {
          toastString = 'UNKNOWN';
        });
      }
    } else {
      // 播放列表为空
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN';
      });
    }
  }

  /// 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      // 如果抽屉打开则关闭抽屉
      setState(() {
        _drawerIsOpen = false;
      });
      return false;
    }

    // 弹出退出确认对话框
    return await ShowExitConfirm.ExitConfirm(context);
  }

  @override
  void dispose() {
    // 禁用保持屏幕唤醒功能
    WakelockPlus.disable();
    _isDisposing = true;
    _disposePlayer();
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

    // 电视加载不同的布局
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

    // 如果不是电视的布局
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
                videoMap: _videoMap,
                playModel: _currentChannel,
                onTapChannel: _onTapChannel,
                isLandscape: false,
                onCloseDrawer: () {  // 添加关闭抽屉的回调
                  setState(() {
                      _drawerIsOpen = false;
                  });
                },
              ),
              toggleFavorite: toggleFavorite,
              currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
              isChannelFavorite: isChannelFavorite,
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
                      ? EmptyPage(onRefresh: _parseData) // 如果播放列表为空，显示错误页面
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
                          onToggleDrawer: () {
                              setState(() {
                                _drawerIsOpen = !_drawerIsOpen;  // 切换抽屉的状态
                              });
                            }
                          ),
                ),
                Offstage(
                  offstage: !_drawerIsOpen, // 控制抽屉显示与隐藏
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _drawerIsOpen = false; // 点击抽屉区域外时，关闭抽屉
                      });
                    },
                    child: ChannelDrawerPage(
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

  /// 弹出选择不同的视频源
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    // 切换到选中的视频播放
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      _playVideo();
    }
  }
}
