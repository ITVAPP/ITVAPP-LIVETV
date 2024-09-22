import 'dart:async';
import 'dart:convert';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:sp_util/sp_util.dart';
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';

/// 封装 M3U 数据
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

  /// 获取本地播放列表，如果本地缓存数据为空，则尝试获取远程播放列表
  Future<M3uResult> getLocalM3uData() async {
    try {
      final m3uDataString = await _getCachedM3uData();
      if (m3uDataString.isEmpty) {
        // 如果本地缓存没有播放列表，返回远程数据
        return await getDefaultM3uData();
      }
      // 本地保存的已经是 PlaylistModel，直接返回
      return M3uResult(data: PlaylistModel.fromString(m3uDataString));
    } catch (e, stackTrace) {
      return M3uResult(errorMessage: '获取播放列表失败');
    }
  }

  /// 获取远程播放列表，支持重试机制
  Future<M3uResult> getDefaultM3uData({Function(int attempt)? onRetry}) async {
    try {
      String m3uData = '';

      // 尝试通过重试机制从远程获取M3U数据
      m3uData = (await _retryRequest<String>(_fetchData, onRetry: onRetry)) ?? '';

      if (m3uData.isEmpty) {
        LogUtil.logError('远程获取M3U数据失败，尝试获取本地缓存数据', 'm3uData为空');

        // 尝试从本地缓存获取 PlaylistModel 数据
        final PlaylistModel cachedData = PlaylistModel.fromString(await _getCachedM3uData());

        // 检查本地缓存是否为空
        if (cachedData == null || cachedData.playList == null) {
          return M3uResult(errorMessage: '获取播放列表失败');
        }

        // 返回本地缓存的 PlaylistModel 数据
        return M3uResult(data: cachedData);
      }

      PlaylistModel parsedData;

      // 判断 m3uData 是否包含多个 URL
      if (m3uData.contains('||')) {
        // 如果有多个 URL，调用 fetchAndMergeM3uData 进行合并
        parsedData = await fetchAndMergeM3uData(m3uData) ?? PlaylistModel();
      } else {
        // 仅有一个 URL，正常解析
        parsedData = await _parseM3u(m3uData);
      }

      // 检查是否成功解析数据
      if (parsedData == null || parsedData.playList == null) {
        return M3uResult(errorMessage: '解析播放列表失败');
      }

      // 获取或创建“我的收藏”列表
      final favoritePlaylist = await getOrCreateFavoriteList();

      // 在 updateFavoriteChannelsWithRemoteData 之前记录 parsedData
      LogUtil.i('解析后的 parsedData.playList 类型: ${parsedData.playList.runtimeType}');
      LogUtil.i('解析后的 parsedData.playList 内容: ${jsonEncode(parsedData.playList)}');
      LogUtil.i('获取我的收藏列表: ${jsonEncode(favoritePlaylist.playList)}');

      // 更新“我的收藏”列表中的频道播放地址
      await updateFavoriteChannelsWithRemoteData(parsedData);

      // 将“我的收藏”列表加入到播放列表中，并设置为第一个分类
      parsedData.playList = _insertFavoritePlaylistFirst(parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>, favoritePlaylist);

      // 保存播放列表到本地缓存
      await _saveCachedM3uData(parsedData.toString());

      // 保存新订阅数据到本地
      await saveLocalData([
        SubScribeModel(
          time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),
          link: 'default',
          selected: true,
        ),
      ]);

      return M3uResult(data: parsedData);
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      return M3uResult(errorMessage: '获取远程播放列表失败');
    }
  }

  /// 获取或创建本地的“我的收藏”列表
  Future<PlaylistModel> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedFavoriteM3uData();
  
    if (favoriteData.isEmpty) {
      // 如果没有缓存数据，创建一个新的“我的收藏”列表
      PlaylistModel favoritePlaylist = PlaylistModel(
        playList: {
          "我的收藏": <String, Map<String, PlayModel>>{}, 
        }
      );
      LogUtil.i('创建了新的我的收藏列表: ${favoritePlaylist.toString()}');
      return favoritePlaylist;
    } else {
      // 如果本地已有缓存数据，转换为 PlaylistModel，解析并返回“我的收藏”列表
      return PlaylistModel.fromString(favoriteData);
    }
  }

  /// 将“我的收藏”列表插入为播放列表的第一个分类
  Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
      Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist,
      PlaylistModel favoritePlaylist) {
    // 创建新的播放列表结构，确保“我的收藏”位于第一个位置
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};

    // 检查并插入“我的收藏”分类到第一个位置
    if (favoritePlaylist.playList?["我的收藏"] != null && favoritePlaylist.playList!["我的收藏"]!.isNotEmpty) {
      updatedPlaylist["我的收藏"] = favoritePlaylist.playList!["我的收藏"]!;
    } else {
      updatedPlaylist["我的收藏"] = {}; // 插入一个空的收藏列表
    }

    // 将其余分类添加到新播放列表中
    originalPlaylist?.forEach((key, value) {
      if (key != "我的收藏") {
        updatedPlaylist[key] = value;
      }
    });

    return updatedPlaylist;
  }

  /// 保存更新后的“我的收藏”列表到本地缓存
  Future<void> saveFavoriteList(PlaylistModel favoritePlaylist) async {
    await SpUtil.putString(favoriteCacheKey, favoritePlaylist.toString());
  }

  /// 从本地缓存中获取“我的收藏”列表
  Future<String> _getCachedFavoriteM3uData() async {
    try {
      return SpUtil.getString(favoriteCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存的“我的收藏”列表失败', e, stackTrace);
      return '';
    }
  }

  /// 更新本地“我的收藏”列表中的频道播放地址
  Future<void> updateFavoriteChannelsWithRemoteData(PlaylistModel remotePlaylist) async {
    // 获取本地的“我的收藏”列表
    PlaylistModel favoritePlaylist = await getOrCreateFavoriteList();

    // 更新“我的收藏”中的频道播放地址
    _updateFavoriteChannels(favoritePlaylist, remotePlaylist);

    // 保存更新后的“我的收藏”列表
    await saveFavoriteList(favoritePlaylist);
  }

  /// 更新“我的收藏”列表中的频道播放地址（仅当远程列表有更新）
  void _updateFavoriteChannels(PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) { 
    // 获取“我的收藏”分类中的频道
    final favoriteCategory = favoritePlaylist.playList?["我的收藏"];
    if (favoriteCategory == null) return;

    // 使用 Set 来记录已更新的 id，避免重复更新
    final Set<String> updatedTvgIds = {};

    // 遍历远程播放列表中的每个频道，基于 id 进行对比和更新
    remotePlaylist.playList?.forEach((category, groups) {
      groups.forEach((groupTitle, channels) {
        channels.forEach((channelName, remoteChannel) {
          if (remoteChannel.id != null && remoteChannel.id!.isNotEmpty) {
            // 如果这个 id 已经被更新过，则跳过
            if (updatedTvgIds.contains(remoteChannel.id!)) return;

            // 使用 id 来更新频道
            _updateFavoriteChannel(favoriteCategory, remoteChannel.id!, remoteChannel);

            // 记录已经更新的 id
            updatedTvgIds.add(remoteChannel.id!);
          }
        });
      });
    });
  }

  /// 更新“我的收藏”中单个频道的播放地址
  void _updateFavoriteChannel(Map<String, Map<String, PlayModel>> favoriteCategory, String tvgId, PlayModel remoteChannel) {
    // 遍历“我的收藏”中的所有组和频道，找到对应的 id 进行更新
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        // 如果收藏中的频道与远程频道的 id 匹配，则进行更新
        if (favoriteChannel.id == tvgId) {
          // 确保远程频道有有效的播放地址
          if (remoteChannel.urls != null && remoteChannel.urls!.isNotEmpty) {
            // 验证并更新播放地址
            final validUrls = remoteChannel.urls!.where((url) => isLiveLink(url)).toList();
            if (validUrls.isNotEmpty) {
              favoriteChannel.urls = validUrls;
            }
          }
        }
      });
    });
  }

  /// 封装的重试机制，最多重试 `retries` 次，并在达到最大重试次数时返回 null
  Future<T?> _retryRequest<T>(
    Future<T?> Function() request, 
    {int retries = 3, Duration retryDelay = const Duration(seconds: 2), Function(int attempt)? onRetry}) async {
    
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await request();
      } catch (e, stackTrace) {
        LogUtil.logError('请求失败，重试第 $attempt 次...', e, stackTrace);
        if (onRetry != null) {
          onRetry(attempt + 1);  // 回调传递重试次数
        }
        if (attempt >= retries - 1) {
          return null;  // 超过最大重试次数，返回 null
        }
        await Future.delayed(retryDelay);  // 延时重试
      }
    }
    return null;
  }

  /// 从本地缓存中获取订阅数据列表
  Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取订阅数据列表失败', e, stackTrace);
      return [];
    }
  }

  /// 获取远程的默认M3U文件数据
  Future<String> _fetchData() async {
    try {
      final defaultM3u = EnvUtil.videoDefaultChannelHost();
      final res = await HttpUtil().getRequest(defaultM3u);
      return res ?? '';  // 返回空字符串表示获取失败
    } catch (e, stackTrace) {
      LogUtil.logError('远程获取默认M3U文件失败', e, stackTrace);
      return '';
    }
  }

  /// 获取并处理多个M3U列表的合并，解析每个URL返回的数据
  Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      List<String> urls = url.split('||');  // 按 "||" 分割多个URL
      final results = await Future.wait(urls.map(_fetchM3uData));
      final playlists = <PlaylistModel>[];

      // 遍历每个返回的M3U数据并解析
      for (var m3uData in results) {
        if (m3uData != null) {
          final parsedPlaylist = await _parseM3u(m3uData);
          playlists.add(parsedPlaylist);
        }
      }

      if (playlists.isEmpty) return null;  // 如果没有解析到任何数据，返回null

      return _mergePlaylists(playlists);  // 合并解析后的播放列表
    } catch (e, stackTrace) {
      LogUtil.logError('获取并合并M3U数据失败', e, stackTrace);
      return null;
    }
  }

  /// 获取M3U数据，设置8秒的超时时间，并使用重试机制
  Future<String?> _fetchM3uData(String url) async {
    try {
      return await _retryRequest<String>(() async => await HttpUtil().getRequest(url).timeout(Duration(seconds: 8)));
    } catch (e, stackTrace) {
      LogUtil.logError('获取M3U数据失败', e, stackTrace);
      return null;
    }
  }

  /// 合并多个 PlaylistModel，避免重复的播放地址
  PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    try {
      PlaylistModel mergedPlaylist = PlaylistModel();
      mergedPlaylist.playList = {};

      // 用于存储已经合并的频道，key 为频道的唯一 id，value 为 PlayModel
      Map<String, PlayModel> mergedChannelsById = {};

      for (PlaylistModel playlist in playlists) {
        playlist.playList?.forEach((category, groups) {
          mergedPlaylist.playList ??= {};
          mergedPlaylist.playList![category] ??= {};

          groups.forEach((groupTitle, channels) {
            mergedPlaylist.playList![category]![groupTitle] ??= {};

            channels.forEach((channelName, channelModel) {
              // 检查频道的 ID 是否有效
              if (channelModel.id != null && channelModel.id!.isNotEmpty) {
                String tvgId = channelModel.id!;

                // 如果频道的播放地址为空，则跳过
                if (channelModel.urls == null || channelModel.urls!.isEmpty) {
                  return; // 跳过当前频道
                }

                // 判断是否已经合并过此 ID 的频道
                if (mergedChannelsById.containsKey(tvgId)) {
                  PlayModel existingChannel = mergedChannelsById[tvgId]!;

                  // 合并播放地址，使用 Set 去重
                  Set<String> existingUrls = existingChannel.urls?.toSet() ?? {};
                  Set<String> newUrls = channelModel.urls?.toSet() ?? {};
                  existingUrls.addAll(newUrls);

                  // 更新合并后的播放地址
                  existingChannel.urls = existingUrls.toList();
                  mergedChannelsById[tvgId] = existingChannel;
                } else {
                  // 如果该频道 ID 尚未被合并，直接添加
                  mergedChannelsById[tvgId] = channelModel;
                }

                // 将合并后的频道放回原来的分组和分类结构中
                // 这里使用 channelName 作为键，以保留原始的频道名结构
                mergedPlaylist.playList![category]![groupTitle]![channelName] = mergedChannelsById[tvgId]!;
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
  Future<String> _getCachedM3uData() async {
    try {
      return SpUtil.getString(m3uCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存M3U数据失败', e, stackTrace);
      return '';
    }
  }

  /// 保存播放列表到本地缓存
  Future<void> _saveCachedM3uData(String data) async {
    try {
      await SpUtil.putString(m3uCacheKey, data);
    } catch (e, stackTrace) {
      LogUtil.logError('保存播放列表到本地缓存失败', e, stackTrace);
    }
  }

  /// 保存订阅模型数据到本地缓存
  Future<bool> saveLocalData(List<SubScribeModel> models) async {
    try {
      return await SpUtil.putObjectList('local_m3u', models.map((e) => e.toJson()).toList()) ?? false;
    } catch (e, stackTrace) {
      LogUtil.logError('保存订阅数据到本地缓存失败', e, stackTrace);
      return false;
    }
  }

  /// 解析 M3U 文件并转换为 PlaylistModel 格式
  Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      // 处理不同的换行符，支持 \r\n 和 \n
      final lines = m3u.split(RegExp(r'\r?\n'));
      final playListModel = PlaylistModel();
      playListModel.playList = <String, Map<String, Map<String, PlayModel>>>{};

      String currentCategory = '所有频道';  // 初始化分类为默认 "所有频道"
      bool hasCategory = false;  // 标记是否有 #CATEGORY 行

      if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
        String tempGroupTitle = '';
        String tempChannelName = '';

        for (int i = 0; i < lines.length; i++) {  // 修改循环终止条件，确保遍历所有行
          String line = lines[i];

          if (line.startsWith('#EXTM3U')) {
            List<String> params = line.replaceAll('"', '').split(' ');
            final tvgUrl = params.firstWhere((element) => element.startsWith('x-tvg-url'), orElse: () => '');
            if (tvgUrl.isNotEmpty) {
              playListModel.epgUrl = tvgUrl.split('=').last;  // 获取EPG URL
            }
          } else if (line.startsWith('#CATEGORY:')) {
            // 识别 #CATEGORY: 标签并提取分类，标记 hasCategory 为 true
            currentCategory = line.replaceFirst('#CATEGORY:', '').trim();
            hasCategory = true;
            if (currentCategory.isEmpty) {
              currentCategory = '所有频道'; // 如果为空则回归默认分类
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

            // 确保 tvg-id 或 tvg-name 必须存在
            String tvgId = params.firstWhere((element) => element.startsWith('tvg-id='), orElse: () => '');
            String tvgName = params.firstWhere((element) => element.startsWith('tvg-name='), orElse: () => '');

            if (tvgId.isEmpty && tvgName.isNotEmpty) {
              // 如果 tvg-id 为空且有 tvg-name，用 tvg-name 代替 tvg-id
              tvgId = tvgName.split('=').last;
            } else if (tvgId.isNotEmpty) {
              // 否则使用 tvg-id
              tvgId = tvgId.split('=').last;
            }

            // 如果 tvg-id 和 tvg-name 都为空，跳过此频道
            if (tvgId.isEmpty) {
              continue;
            }

            // 确保在没有 #CATEGORY 时，currentCategory 始终是 '所有频道'
            if (!hasCategory) {
              currentCategory = '所有频道';
            }

            if (groupStr.isNotEmpty) {
              tempGroupTitle = groupStr.split('=').last;
              tempChannelName = lineList.last;

              Map<String, Map<String, PlayModel>> categoryMap = playListModel.playList?[currentCategory] ?? {};
              Map<String, PlayModel> groupMap = categoryMap[tempGroupTitle] ?? {};
              PlayModel channel = groupMap[tempChannelName] ?? PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

              // 检查索引越界问题，避免 lines[i + 1] 或 lines[i + 2] 越界
              if (i + 1 < lines.length && isLiveLink(lines[i + 1])) {
                channel.urls ??= [];
                if (lines[i + 1].isNotEmpty) {
                  channel.urls!.add(lines[i + 1]);
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![currentCategory] = categoryMap;
                i += 1;  // 跳过已经处理的下一行
              } else if (i + 2 < lines.length && isLiveLink(lines[i + 2])) {
                channel.urls ??= [];
                if (lines[i + 2].isNotEmpty) {
                  channel.urls!.add(lines[i + 2].toString());
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![currentCategory] = categoryMap;
                i += 2;  // 跳过已经处理的后两行
              }

              // 处理完当前频道后，重置 hasCategory，但保留 currentCategory
              hasCategory = false;
            }
          } else if (isLiveLink(line)) {
            playListModel.playList?[currentCategory]?[tempGroupTitle]?[tempChannelName]?.urls ??= [];
            if (line.isNotEmpty) {
              playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls!.add(line);
            }
          }
        }
      } else {
        // 处理非标准M3U文件
        String tempGroup = S.current.defaultText;
        for (int i = 0; i < lines.length; i++) {  // 修改循环终止条件，确保遍历所有行
          final line = lines[i];
          final lineList = line.split(',');
          if (lineList.length >= 2) {
            final groupTitle = lineList[0];
            final channelLink = lineList[1];
            if (isLiveLink(channelLink)) {
              Map<String, Map<String, PlayModel>> categoryMap = playListModel.playList?[tempGroup] ?? {};
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
  bool isLiveLink(String link) {
    const protocols = ['http', 'https', 'rtmp', 'rtsp', 'mms', 'ftp'];
    return protocols.any((protocol) => link.toLowerCase().startsWith(protocol));
  }
}
