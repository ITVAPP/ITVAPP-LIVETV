import 'dart:async';
import 'dart:convert';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';
import 'log_util.dart';

/// 封装 M3U 数据或错误信息
class M3uResult {
  final PlaylistModel? data;
  final String? errorMessage;

  M3uResult({this.data, this.errorMessage});
}

class M3uUtil {
  M3uUtil._();

  /// 定义“我的收藏”列表的本地缓存键
  static const String favoriteCacheKey = 'favorite_m3u_cache';
  /// 定义播放列表的本地缓存键
  static const String m3uCacheKey = 'm3u_cache';

  /// 通用缓存获取方法，基于键名获取缓存数据
  static Future<String> _getCachedData(String cacheKey) async {
    try {
      return SpUtil.getString(cacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存数据失败', e, stackTrace);
      return '';
    }
  }

  /// 通用缓存保存方法，基于键名保存数据
  static Future<void> _saveCachedData(String cacheKey, String data) async {
    try {
      await SpUtil.putString(cacheKey, data);
    } catch (e, stackTrace) {
      LogUtil.logError('保存数据到本地缓存失败', e, stackTrace);
    }
  }

  /// 通用的远程数据获取和缓存回退逻辑
  static Future<M3uResult> _fetchRemoteOrCacheData({
    required Future<String> Function() fetchRemote,
    required String cacheKey,
    required Future<PlaylistModel?> Function(String data) parseData,
  }) async {
    try {
      String remoteData = await _retryRequest<String>(fetchRemote) ?? '';
      if (remoteData.isNotEmpty) {
        // 远程数据成功获取，解析并保存缓存
        final parsedData = await parseData(remoteData);
        if (parsedData != null && parsedData.playList != null) {
          await _saveCachedData(cacheKey, remoteData);
          return M3uResult(data: parsedData);
        }
        return M3uResult(errorMessage: '解析远程数据失败');
      } else {
        // 远程数据为空，从本地缓存读取
        final cachedDataString = await _getCachedData(cacheKey);
        if (cachedDataString.isEmpty) {
          return M3uResult(errorMessage: '没有可用的播放列表数据');
        }
        final cachedData = await parseData(cachedDataString);
        return cachedData != null
            ? M3uResult(data: cachedData)
            : M3uResult(errorMessage: '读取缓存数据失败');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程数据或缓存数据失败', e, stackTrace);
      return M3uResult(errorMessage: '获取数据失败');
    }
  }

  /// 获取本地播放列表，如果本地缓存数据为空，则尝试获取远程播放列表
  static Future<M3uResult> getLocalM3uData() async {
    return await _fetchRemoteOrCacheData(
      fetchRemote: _fetchData,
      cacheKey: m3uCacheKey,
      parseData: (data) => Future.value(PlaylistModel.fromString(data)),
    );
  }

  /// 获取远程播放列表，支持重试机制
  static Future<M3uResult> getDefaultM3uData({Function(int attempt)? onRetry}) async {
    return await _fetchRemoteOrCacheData(
      fetchRemote: _fetchData,
      cacheKey: m3uCacheKey,
      parseData: (data) async {
        PlaylistModel parsedData;
        parsedData = await _parseM3u(data);

        // 如果播放列表为空，返回错误信息
        if (parsedData.playList == null) {
          return null;
        }

        // 获取或创建“我的收藏”列表并更新
        final favoritePlaylist = await getOrCreateFavoriteList();
        await updateFavoriteChannelsWithRemoteData(parsedData);

        // 将“我的收藏”列表加入到播放列表中
        parsedData.playList = _insertFavoritePlaylistFirst(parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>, favoritePlaylist);

        return parsedData;
      },
    );
  }

  /// 获取或创建本地的“我的收藏”列表
  static Future<PlaylistModel> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedData(favoriteCacheKey);
    if (favoriteData.isEmpty) {
      PlaylistModel favoritePlaylist = PlaylistModel();
      favoritePlaylist.playList = {
        "我的收藏": {},
      };
      return favoritePlaylist;
    } else {
      return PlaylistModel.fromString(favoriteData);
    }
  }

  /// 将“我的收藏”列表插入为播放列表的第一个分类
  static Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
      Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist,
      PlaylistModel favoritePlaylist) {
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};
    updatedPlaylist["我的收藏"] = favoritePlaylist.playList?["我的收藏"] ?? {};
    originalPlaylist?.forEach((key, value) {
      if (key != "我的收藏") {
        updatedPlaylist[key] = value;
      }
    });
    return updatedPlaylist;
  }

  /// 保存更新后的“我的收藏”列表到本地缓存
  static Future<void> saveFavoriteList(PlaylistModel favoritePlaylist) async {
    await _saveCachedData(favoriteCacheKey, favoritePlaylist.toString());
  }

  /// 更新本地“我的收藏”列表中的频道播放地址
  static Future<void> updateFavoriteChannelsWithRemoteData(PlaylistModel remotePlaylist) async {
    PlaylistModel favoritePlaylist = await getOrCreateFavoriteList();
    _updateFavoriteChannels(favoritePlaylist, remotePlaylist);
    await saveFavoriteList(favoritePlaylist);
  }

  /// 更新“我的收藏”列表中的频道播放地址
  static void _updateFavoriteChannels(PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) {
    final favoriteCategory = favoritePlaylist.playList?["我的收藏"];
    if (favoriteCategory == null) return;

    final Set<String> updatedTvgIds = {};

    remotePlaylist.playList?.forEach((category, groups) {
      groups.forEach((groupTitle, channels) {
        channels.forEach((channelName, remoteChannel) {
          if (remoteChannel.id != null && remoteChannel.id!.isNotEmpty) {
            if (updatedTvgIds.contains(remoteChannel.id!)) return;
            _updateChannelIfExists(favoriteCategory, remoteChannel);
            updatedTvgIds.add(remoteChannel.id!);
          }
        });
      });
    });
  }

  /// 更新频道的逻辑
  static void _updateChannelIfExists(Map<String, Map<String, PlayModel>> favoriteCategory, PlayModel remoteChannel) {
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        if (favoriteChannel.id == remoteChannel.id) {
          if (remoteChannel.urls != null && remoteChannel.urls!.isNotEmpty) {
            final validUrls = remoteChannel.urls!.where((url) => isLiveLink(url)).toList();
            if (validUrls.isNotEmpty) {
              favoriteChannel.urls = validUrls;
            }
          }
        }
      });
    });
  }

  /// 重试机制，最多重试 `retries` 次，并在达到最大重试次数时返回 null
  static Future<T?> _retryRequest<T>(
    Future<T?> Function() request, 
    {int retries = 3, Duration retryDelay = const Duration(seconds: 2), Function(int attempt)? onRetry}) async {
    
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await request();
      } catch (e, stackTrace) {
        if (onRetry != null) {
          onRetry(attempt + 1);  // 回调传递重试次数
        }
        if (attempt >= retries - 1) {
          return null;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }

  /// 从本地缓存中获取订阅数据列表
  static Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取订阅数据列表失败', e, stackTrace);
      return [];
    }
  }

  /// 获取远程的默认M3U文件数据
  static Future<String> _fetchData() async {
    try {
      final defaultM3u = EnvUtil.videoDefaultChannelHost();
      final res = await HttpUtil().getRequest(defaultM3u);
      return res ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('远程获取默认M3U文件失败', e, stackTrace);
      return '';
    }
  }

  /// 获取并处理多个M3U列表的合并，解析每个URL返回的数据
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      List<String> urls = url.split('||');
      final results = await Future.wait(urls.map(_fetchM3uData));
      final playlists = <PlaylistModel>[];

      for (var m3uData in results) {
        if (m3uData != null) {
          final parsedPlaylist = await _parseM3u(m3uData);
          playlists.add(parsedPlaylist);
        }
      }

      if (playlists.isEmpty) return null;

      return _mergePlaylists(playlists);
    } catch (e, stackTrace) {
      LogUtil.logError('获取并合并M3U数据失败', e, stackTrace);
      return null;
    }
  }

  /// 获取M3U数据，设置8秒的超时时间，并使用重试机制
  static Future<String?> _fetchM3uData(String url) async {
    try {
      return await _retryRequest<String>(() async => await HttpUtil().getRequest(url).timeout(Duration(seconds: 8)));
    } catch (e, stackTrace) {
      LogUtil.logError('获取M3U数据失败', e, stackTrace);
      return null;
    }
  }

  /// 合并多个 PlaylistModel，避免重复的播放地址
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    try {
      PlaylistModel mergedPlaylist = PlaylistModel();
      mergedPlaylist.playList = {};

      for (PlaylistModel playlist in playlists) {
        playlist.playList?.forEach((category, groups) {
          mergedPlaylist.playList ??= {};
          mergedPlaylist.playList![category] ??= {};

          groups.forEach((groupTitle, channels) {
            mergedPlaylist.playList![category]![groupTitle] ??= {};

            channels.forEach((channelName, channelModel) {
              if (channelModel.id != null && channelModel.id!.isNotEmpty) {
                String tvgId = channelModel.id!;

                if (channelModel.urls == null || channelModel.urls!.isEmpty) {
                  return;
                }

                if (mergedPlaylist.playList![category]![groupTitle]!.containsKey(tvgId)) {
                  PlayModel existingChannel = mergedPlaylist.playList![category]![groupTitle]![tvgId]!;

                  Set<String> existingUrls = existingChannel.urls?.toSet() ?? {};
                  Set<String> newUrls = channelModel.urls?.toSet() ?? {};
                  existingUrls.addAll(newUrls);

                  existingChannel.urls = existingUrls.toList();
                  mergedPlaylist.playList![category]![groupTitle]![tvgId] = existingChannel;
                } else {
                  mergedPlaylist.playList![category]![groupTitle]![tvgId] = channelModel;
                }
              }
            });
          });
        });
      }

      return mergedPlaylist;
    } catch (e, stackTrace) {
      LogUtil.logError('合并播放列表失败', e, stackTrace);
      return PlaylistModel();
    }
  }

  /// 获取本地缓存播放列表
  static Future<String> _getCachedM3uData() async {
    return await _getCachedData(m3uCacheKey);
  }

  /// 保存播放列表到本地缓存
  static Future<void> _saveCachedM3uData(String data) async {
    await _saveCachedData(m3uCacheKey, data);
  }

  /// 保存订阅模型数据到本地缓存
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    try {
      return await SpUtil.putObjectList('local_m3u', models.map((e) => e.toJson()).toList()) ?? false;
    } catch (e, stackTrace) {
      LogUtil.logError('保存订阅数据到本地缓存失败', e, stackTrace);
      return false;
    }
  }

  /// 解析 M3U 文件并转换为 PlaylistModel 格式
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final lines = m3u.split('\n');
      final playListModel = PlaylistModel();
      playListModel.playList = <String, Map<String, Map<String, PlayModel>>>{};

      if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
        String tempGroupTitle = '';
        String tempChannelName = '';
        String currentCategory = '所有频道';
        bool hasCategory = false;

        for (int i = 0; i < lines.length - 1; i++) {
          String line = lines[i];

          if (line.startsWith('#EXTM3U')) {
            List<String> params = line.replaceAll('"', '').split(' ');
            final tvgUrl = params.firstWhere((element) => element.startsWith('x-tvg-url'), orElse: () => '');
            if (tvgUrl.isNotEmpty) {
              playListModel.epgUrl = tvgUrl.split('=').last;
            }
          } else if (line.startsWith('#CATEGORY:')) {
            currentCategory = line.replaceFirst('#CATEGORY:', '').trim();
            hasCategory = true;
            if (currentCategory.isEmpty) {
              currentCategory = '所有频道';
            }
          } else if (line.startsWith('#EXTINF:')) {
            if (line.startsWith('#EXTINF:-1,')) {
              line = line.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
            }
            final lineList = line.split(',');
            List<String> params = lineList.first.replaceAll('"', '').split(' ');

            final groupStr = params.firstWhere((element) => element.startsWith('group-title='), orElse: () => 'group-title=${S.current.defaultText}');
            if (groupStr.isNotEmpty && groupStr.contains('=')) {
              tempGroupTitle = groupStr.split('=').last;
            }

            String tvgLogo = params.firstWhere((element) => element.startsWith('tvg-logo='), orElse: () => '');
            if (tvgLogo.isNotEmpty && tvgLogo.contains('=')) {
              tvgLogo = tvgLogo.split('=').last;
            }

            String tvgId = params.firstWhere((element) => element.startsWith('tvg-name='), orElse: () => '');
            if (tvgId.isEmpty) {
              tvgId = params.firstWhere((element) => element.startsWith('tvg-id='), orElse: () => '');
            }
            if (tvgId.isNotEmpty && tvgId.contains('=')) {
              tvgId = tvgId.split('=').last;
            }

            if (groupStr.isNotEmpty) {
              tempGroupTitle = groupStr.split('=').last;
              tempChannelName = lineList.last;

              if (!hasCategory) {
                currentCategory = '所有频道';
              }
              Map<String, Map<String, PlayModel>> categoryMap = playListModel.playList![currentCategory] ?? {};
              Map<String, PlayModel> groupMap = categoryMap[tempGroupTitle] ?? {};
              PlayModel channel = groupMap[tempChannelName] ?? PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

              final lineNext = lines[i + 1];
              if (isLiveLink(lineNext)) {
                channel.urls ??= [];
                if (lineNext.isNotEmpty) {
                  channel.urls!.add(lineNext);
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![currentCategory] = categoryMap;
                i += 1;
              } else if (isLiveLink(lines[i + 2])) {
                channel.urls ??= [];
                if (lines[i + 2].isNotEmpty) {
                  channel.urls!.add(lines[i + 2].toString());
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![currentCategory] = categoryMap;
                i += 2;
              }

              hasCategory = false;
            }
          } else if (isLiveLink(line)) {
            playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls ??= [];
            if (line.isNotEmpty) {
              playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls!.add(line);
            }
          }
        }
      } else {
        String tempGroup = S.current.defaultText;
        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i];
          final lineList = line.split(',');
          if (lineList.length >= 2) {
            final groupTitle = lineList[0];
            final channelLink = lineList[1];
            if (isLiveLink(channelLink)) {
              Map<String, Map<String, PlayModel>> categoryMap = playListModel.playList![tempGroup] ?? {};
              Map<String, PlayModel> groupMap = categoryMap[groupTitle] ?? {};
              final channel = groupMap[groupTitle] ?? PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
              channel.urls ??= [];
              if (channelLink.isNotEmpty) {
                channel.urls!.add(channelLink);
              }
              groupMap[groupTitle] = channel;
              categoryMap[groupTitle] = groupMap;
              playListModel.playList![tempGroup] = categoryMap;
            } else {
              tempGroup = groupTitle == '' ? '${S.current.defaultText}${i + 1}' : groupTitle;
              if (playListModel.playList![tempGroup] == null) {
                playListModel.playList![tempGroup] = <String, Map<String, PlayModel>>{};
              }
            }
          }
        }
      }
      return playListModel;
    } catch (e, stackTrace) {
      LogUtil.logError('解析M3U文件失败', e, stackTrace);
      return PlaylistModel();
    }
  }

  /// 通过遍历协议列表判断链接是否为有效的直播链接
  static bool isLiveLink(String link) {
    const protocols = ['http', 'https', 'rtmp', 'rtsp', 'mms', 'ftp'];
    return protocols.any((protocol) => link.toLowerCase().startsWith(protocol));
  }
}
