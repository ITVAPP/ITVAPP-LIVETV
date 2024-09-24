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
import 'util/epg_util.dart';
import 'util/env_util.dart';
import 'util/check_version_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'util/dialog_util.dart';
import 'widget/empty_page.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  /// 定义“我的收藏”列表的本地缓存键
  static const String favoriteCacheKey = 'favorite_m3u_cache';
  /// 定义播放列表的本地缓存键
  static const String m3uCacheKey = 'm3u_cache';

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

  // 快速切换时的竞态条件
  bool _isSwitchingChannel = false;

  // 超时检测时间
  final int timeoutSeconds = defaultTimeoutSeconds;

  StreamUrl? _streamUrl;

  // 收藏列表相关
  PlaylistModel favoriteList = PlaylistModel(playList: {});

  /// 播放新视频前，解析当前频道的视频源
  Future<void> _playVideo() async {

    LogUtil.i('播放前检查竞态条件：$_isSwitchingChannel');
    LogUtil.i('播放前检查资源释放：$_isDisposing');

    if (_currentChannel == null || _isSwitchingChannel || _isDisposing) return;

    // 释放旧的资源
    await _disposePlayer();

    _isSwitchingChannel = true;

    // 更新界面上的加载提示文字
    toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    setState(() {});

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

      // 播放成功，重置重试次数计数器
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

  /// 播放器资源释放
  Future<void> _disposePlayer() async {
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
      title: S.of(context).foundStreamTitle,  // 动态传入标题
      content: S.of(context).streamUrlContent(url),  // 动态传入内容
      positiveButtonLabel: S.of(context).playButton,
      onPositivePressed: () {
        Navigator.of(context).pop(true);  // 用户确认播放
      },
      negativeButtonLabel: S.of(context).cancelButton,
      onNegativePressed: () {
        Navigator.of(context).pop(false);  // 用户取消播放
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

    // 加载收藏列表
    _loadFavorites().then((_) {
      setState(() {});  // 收藏加载完成后刷新 UI
    }).catchError((error) {
      LogUtil.logError('初始化收藏列表时出错', error);
    });
  }

  /// 加载或初始化“我的收藏”列表
  Future<void> _loadFavorites() async {
    final favoriteData = await _getCachedFavoriteM3uData();

    if (favoriteData.isEmpty) {
      // 如果没有缓存数据，初始化空的收藏列表
      favoriteList = PlaylistModel(
        playList: {"我的收藏": <String, Map<String, PlayModel>>{}},
      );
    } else {
      // 如果有缓存数据，解析并加载“我的收藏”列表
      favoriteList = PlaylistModel.fromString(favoriteData);
    }
    LogUtil.i('初始收藏列表: ${jsonEncode(favoriteList.playList)}');
    setState(() {});
  }

  /// 从本地缓存中获取“我的收藏”列表
  static Future<String> _getCachedFavoriteM3uData() async {
    try {
      return SpUtil.getString(LiveHomePage.favoriteCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存的“我的收藏”列表失败', e, stackTrace);
      return '';
    }
  }

  /// 保存更新后的“我的收藏”到本地缓存
  static Future<void> _saveFavoriteList(PlaylistModel favoritePlaylist) async {
    try {
      await SpUtil.putString(LiveHomePage.favoriteCacheKey, favoritePlaylist.toString());
      LogUtil.i('新的收藏列表: ${jsonEncode(favoritePlaylist.playList)}');
      LogUtil.i('收藏列表成功保存到本地缓存');
    } catch (e, stackTrace) {
      LogUtil.logError('保存收藏列表到本地缓存失败', e, stackTrace);
      throw '收藏保存失败'; // 确保错误被捕获并处理
    }
  }

  // 获取当前频道的分组名字
  String getGroupName(String channelId) {
    return _currentChannel?.group ?? '';
  }

  // 获取当前频道的名字
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
    return favoriteList.playList['我的收藏']?[groupName]?.containsKey(channelName) ?? false;
  }

  // 添加或取消收藏
  void toggleFavorite(String channelId) async {
    // 确保 '我的收藏' 结构已存在
    if (favoriteList.playList['我的收藏'] == null) {
      favoriteList.playList['我的收藏'] = {};
    }
    LogUtil.i('修改前的收藏列表: ${jsonEncode(favoriteList.playList)}');
    bool isFavoriteChanged = false;

    if (isChannelFavorite(channelId)) {
      // 取消收藏
      String groupName = getGroupName(channelId);
      String channelName = getChannelName(channelId);
      favoriteList.playList['我的收藏']![groupName]?.remove(channelName);
      if (favoriteList.playList['我的收藏']![groupName]?.isEmpty ?? true) {
        favoriteList.playList['我的收藏']!.remove(groupName);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('频道已从收藏中移除'), duration: Duration(seconds: 3))
      );
      isFavoriteChanged = true;
    } else {
      // 添加收藏
      String groupName = getGroupName(channelId);
      String channelName = getChannelName(channelId);

      if (favoriteList.playList['我的收藏']![groupName] == null) {
        favoriteList.playList['我的收藏']![groupName] = {};
      }

      PlayModel newFavorite = PlayModel(
        id: channelId,
        title: channelName,
        group: groupName,
        urls: getPlayUrls(channelId),
        logo: _currentChannel?.logo,
      );
      favoriteList.playList['我的收藏']![groupName]![channelName] = newFavorite;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('频道已添加到收藏'), duration: Duration(seconds: 3))
      );
      isFavoriteChanged = true;
      LogUtil.i('修改后的收藏列表: ${jsonEncode(favoriteList.playList)}');
    }

    // 仅在收藏状态改变时更新UI
    if (isFavoriteChanged) {
      try {
        await _saveFavoriteList(favoriteList);
        setState(() {});
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存收藏状态失败: $error'), duration: Duration(seconds: 3))
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

          // 返回第一个有效播放地址
          for (PlayModel? channel in channelMap.values) {
            if (channel?.urls != null && channel!.urls!.isNotEmpty) {
              return channel;
            }
          }
        }
      } else if (playList[category] is Map<String, PlayModel>) {
        // 两层结构处理
        Map<String, PlayModel> channelMap = playList[category] ?? {};

        // 返回第一个有效播放地址
        for (PlayModel? channel in channelMap.values) {
          if (channel?.urls != null && channel!.urls!.isNotEmpty) {
            return channel;
          }
        }
      }
    }
    return null;
  }

  /// 异步加载视频数据和版本检测
  _loadData() async {
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist();
      CheckVersionUtil.checkVersion(context, false, false);
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

  /// 处理播放列表和 EPG 数据
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      // 获取第一个可用的频道
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
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

      // 处理 EPG 数据加载
      if (_videoMap?.epgUrl?.isNotEmpty ?? false) {
        try {
          EpgUtil.loadEPGXML(_videoMap!.epgUrl!);
        } catch (e, stackTrace) {
          LogUtil.logError('加载EPG数据时出错', e, stackTrace);
        }
      } else {
        EpgUtil.resetEPGXML();
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
          toggleFavorite: toggleFavorite,
          isChannelFavorite: isChannelFavorite,
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
                      isChannelFavorite: isChannelFavorite,
                      toggleFavorite: toggleFavorite,
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
                            fontSize: 15,
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

      // 切换到选中的视频播放
      if (selectedIndex != null && _sourceIndex != selectedIndex) {
        _sourceIndex = selectedIndex;
        _playVideo();
      }
    } catch (modalError, modalStackTrace) {
      LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
    }
  }
}
