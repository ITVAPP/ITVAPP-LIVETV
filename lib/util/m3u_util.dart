import 'dart:async';
import 'dart:convert';
import 'package:sp_util/sp_util.dart';
import 'package:intl/intl.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';
import '../config.dart';

/// 封装 M3U 数据
class M3uResult {
  final PlaylistModel? data;
  final String? errorMessage;
  const M3uResult({this.data, this.errorMessage}); // 添加const构造函数以优化内存
}

class M3uUtil {
  M3uUtil._();
  
  // 缓存常用的正则表达式以提高性能
  static final RegExp _newlineRegex = RegExp(r'\r?\n');
  static final RegExp _protocolRegex = RegExp(r'^(http|https|rtmp|rtsp|mms|ftp)', caseSensitive: false);
  
  // 常用字符串常量化以减少字符串创建
  static const String _extinfPrefix = '#EXTINF:';
  static const String _categoryPrefix = '#CATEGORY:';
  static const String _extm3uPrefix = '#EXTM3U';

  // 添加内存缓存以减少磁盘IO
  static PlaylistModel? _cachedPlaylist;
  static DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 30);
  
  /// 获取本地播放列表，如数据为空，则尝试获取远程播放列表
  static Future<M3uResult> getLocalM3uData() async {
    try {
      // 检查内存缓存是否有效
      if (_cachedPlaylist != null && 
          _lastCacheTime != null &&
          DateTime.now().difference(_lastCacheTime!) < _cacheValidDuration) {
        return M3uResult(data: _cachedPlaylist);
      }

      final m3uDataString = await _getCachedM3uData();
      if (m3uDataString.isEmpty) {
        return await getDefaultM3uData();
      }
      
      _cachedPlaylist = PlaylistModel.fromString(m3uDataString);
      _lastCacheTime = DateTime.now();
      return M3uResult(data: _cachedPlaylist);
    } catch (e, stackTrace) {
      return M3uResult(errorMessage: S.current.getm3udataerror);
    }
  }

  /// 获取远程播放列表
  static Future<M3uResult> getDefaultM3uData({Function(int attempt)? onRetry}) async {
    try {
      String m3uData = '';

      // 尝试通过重试机制获取远程播放列表
      m3uData = (await _retryRequest<String>(_fetchData, onRetry: onRetry)) ?? '';

      if (m3uData.isEmpty) {
        LogUtil.logError('获取远程播放列表失败，尝试获取本地缓存数据', 'm3uData为空');

        // 尝试从本地缓存获取 PlaylistModel 数据
        final PlaylistModel cachedData = PlaylistModel.fromString(await _getCachedM3uData());

        // 检查本地缓存是否为空
        if (cachedData == null || cachedData.playList == null) {
          return M3uResult(errorMessage: S.current.getm3udataerror);
        }

        return M3uResult(data: cachedData);
      }

      PlaylistModel parsedData;

      // 判断 m3uData 是否包含多个 URL
      if (m3uData.contains('||')) {
        // 如果有多个 URL，调用 fetchAndMergeM3uData 进行合并
        parsedData = await fetchAndMergeM3uData(m3uData) ?? PlaylistModel();
      } else {
        parsedData = await _parseM3u(m3uData);
      }

      // 检查是否成功解析数据
      if (parsedData == null || parsedData.playList == null) {
        return M3uResult(errorMessage: S.current.getm3udataerror);
      }

      LogUtil.i('解析后的播放列表内容: ${parsedData.playList}\n解析后的播放列表类型: ${parsedData.playList.runtimeType}');

      // 获取或创建收藏列表
      final favoritePlaylist = await getOrCreateFavoriteList();

      // 更新收藏列表中的频道播放地址
      await updateFavoriteChannelsWithRemoteData(parsedData, favoritePlaylist);

      // 将收藏列表加入到播放列表中，并设置为第一个分类
      parsedData.playList = _insertFavoritePlaylistFirst(
          parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>,
          favoritePlaylist);

      // 保存播放列表到本地缓存
      await saveCachedM3uData(parsedData.toString());
      
      LogUtil.i('保存后的播放列表类型: ${parsedData.playList.runtimeType}\n保存后的播放列表内容: ${parsedData.playList}');

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
      return M3uResult(errorMessage: S.current.getm3udataerror);
    }
  }
  
  /// 获取或创建本地的收藏列表
  static Future<PlaylistModel> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedFavoriteM3uData();

    if (favoriteData.isEmpty) {
      // 如果没有缓存数据，创建一个新的收藏列表
      PlaylistModel favoritePlaylist = PlaylistModel(
        playList: {
          Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 确保结构和播放列表一致
        },
      );
      LogUtil.i('创建的收藏列表类型: ${favoritePlaylist.playList.runtimeType}\n创建的收藏列表: ${favoritePlaylist.playList}');
      return favoritePlaylist;
    } else {
      // 如果本地已有缓存数据，转换为 PlaylistModel
      PlaylistModel favoritePlaylist = PlaylistModel.fromString(favoriteData);
      LogUtil.i('缓存的收藏列表: ${favoriteData}\n解析后的收藏列表: ${favoritePlaylist}\n解析后的收藏列表类型: ${favoritePlaylist.playList.runtimeType}');
      return favoritePlaylist;
    }
  }

  /// 将收藏列表插入为播放列表的第一个分类
  static Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
      Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist,
      PlaylistModel favoritePlaylist) {
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};

    // 如果 parsedData.playList 中已有同名的收藏列表，直接替换
    if (originalPlaylist?[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    } 
    // 检查并确保即使为空也能插入收藏分类
    else if (favoritePlaylist.playList?[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    }

    // 将其余分类添加到新播放列表中
    originalPlaylist?.forEach((key, value) {
      if (key != Config.myFavoriteKey) {
        updatedPlaylist[key] = value;
      }
    });

    return updatedPlaylist;
  }

  /// 保存更新后的收藏列表到本地缓存
  static Future<void> saveFavoriteList(PlaylistModel favoritePlaylist) async {
    await SpUtil.putString(Config.favoriteCacheKey, favoritePlaylist.toString());
  }

  /// 从本地缓存中获取收藏列表
  static Future<String> _getCachedFavoriteM3uData() async {
    try {
      return SpUtil.getString(Config.favoriteCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地收藏列表失败', e, stackTrace);
      return '';
    }
  }

  /// 获取远程播放列表
  static Future<String> _fetchData() async {
    try {
      final defaultM3u = EnvUtil.videoDefaultChannelHost();
      final timeParam = DateFormat('yyyyMMddHH').format(DateTime.now());
      
      // 使用 Uri 类构建 URL，避免字符串拼接
      final uri = Uri.parse(defaultM3u).replace(
        queryParameters: {'time': timeParam}
      );

      return await HttpUtil().getRequest(uri.toString()) ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      return '';
    }
  }

  /// 处理 EXTM3U 标签
  static void _processExtM3U(String line, PlaylistModel model) {
    List<String> params = line.replaceAll('"', '').split(' ');
    final tvgUrl = params
        .firstWhere((element) => element.startsWith('x-tvg-url'),
            orElse: () => '')
        .split('=')
        .last;
    if (tvgUrl.isNotEmpty) {
      model.epgUrl = tvgUrl;
    }
  }

  /// 处理 CATEGORY 标签
  static String _processCategory(String line) {
    final category = line.substring(_categoryPrefix.length).trim();
    return category.isEmpty ? Config.allChannelsKey : category;
  }
  
  /// 解析 M3U 文件并转换为 PlaylistModel 格式
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final lines = m3u.split(_newlineRegex);
      final playListModel = PlaylistModel();
      playListModel.playList = {};

      String currentCategory = Config.allChannelsKey;
      bool hasCategory = false;
      String tempGroupTitle = '';
      String tempChannelName = '';

      if (m3u.startsWith(_extm3uPrefix) || m3u.startsWith(_extinfPrefix)) {
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i];

          if (line.startsWith(_extm3uPrefix)) {
            _processExtM3U(line, playListModel);
          } else if (line.startsWith(_categoryPrefix)) {
            currentCategory = _processCategory(line);
            hasCategory = true;
          } else if (line.startsWith(_extinfPrefix)) {
            if (line.startsWith('#EXTINF:-1,')) {
              line = line.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
            }
            final lineList = line.split(',');
            List<String> params = lineList.first.replaceAll('"', '').split(' ');

            final groupStr = params.firstWhere(
                (element) => element.startsWith('group-title='),
                orElse: () => 'group-title=${S.current.defaultText}');
                
            String tvgLogo = params.firstWhere(
                (element) => element.startsWith('tvg-logo='),
                orElse: () => '');
            if (tvgLogo.isNotEmpty && tvgLogo.contains('=')) {
              tvgLogo = tvgLogo.split('=').last;
            }

            String tvgId = params.firstWhere(
                (element) => element.startsWith('tvg-id='),
                orElse: () => '');
            String tvgName = params.firstWhere(
                (element) => element.startsWith('tvg-name='),
                orElse: () => '');

            if (tvgId.isEmpty && tvgName.isNotEmpty) {
              tvgId = tvgName.split('=').last;
            } else if (tvgId.isNotEmpty) {
              tvgId = tvgId.split('=').last;
            }

            if (tvgId.isEmpty) continue;

            if (groupStr.isNotEmpty && groupStr.contains('=')) {
              tempGroupTitle = groupStr.split('=').last;
              tempChannelName = lineList.last;

              Map<String, Map<String, PlayModel>> categoryMap =
                  playListModel.playList?[currentCategory] ?? {};
              Map<String, PlayModel> groupMap = categoryMap[tempGroupTitle] ?? {};
              PlayModel channel = groupMap[tempChannelName] ??
                  PlayModel(
                      id: tvgId,
                      group: tempGroupTitle,
                      logo: tvgLogo,
                      title: tempChannelName,
                      urls: []);

              // 检查索引越界问题，避免 lines[i + 1] 或 lines[i + 2] 越界
              if (i + 1 < lines.length && isLiveLink(lines[i + 1])) {
                channel.urls ??= [];
                if (lines[i + 1].isNotEmpty) {
                  channel.urls!.add(lines[i + 1]);
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![currentCategory] = categoryMap;
                i += 1;
              } else if (i + 2 < lines.length && isLiveLink(lines[i + 2])) {
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
            playListModel.playList?[currentCategory]?[tempGroupTitle]
                    ?[tempChannelName]
                ?.urls ??= [];
            if (line.isNotEmpty) {
              playListModel.playList![currentCategory]![tempGroupTitle]!
                  [tempChannelName]!.urls!.add(line);
            }
          }
        }
      } else {
        // 处理非标准M3U文件
        String tempGroup = S.current.defaultText;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lineList = line.split(',');
          if (lineList.length >= 2) {
            final groupTitle = lineList[0];
            final channelLink = lineList[1];
            if (isLiveLink(channelLink)) {
              Map<String, Map<String, PlayModel>> categoryMap =
                  playListModel.playList?[tempGroup] ?? {};
              Map<String, PlayModel> groupMap = categoryMap[groupTitle] ?? {};
              final channel = groupMap[groupTitle] ??
                  PlayModel(
                      group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
              channel.urls ??= [];
              if (channelLink.isNotEmpty) {
                channel.urls!.add(channelLink);
              }
              groupMap[groupTitle] = channel;
              categoryMap[groupTitle] = groupMap;
              playListModel.playList![tempGroup] = categoryMap;
            } else {
              tempGroup =
                  groupTitle == '' ? '${S.current.defaultText}${i + 1}' : groupTitle;
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
  
  /// 获取并处理多个M3U列表的合并，解析每个URL返回的数据
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      List<String> urls = url.split('||'); // 按 "||" 分割多个URL
      final results = await Future.wait(urls.map(_fetchM3uData));
      final playlists = <PlaylistModel>[];

      // 遍历每个返回的M3U数据并解析
      for (var m3uData in results) {
        if (m3uData != null) {
          final parsedPlaylist = await _parseM3u(m3uData);
          playlists.add(parsedPlaylist);
        }
      }

      if (playlists.isEmpty) return null;

      return _mergePlaylists(playlists); // 合并解析后的播放列表
    } catch (e, stackTrace) {
      LogUtil.logError('合并播放列表失败', e, stackTrace);
      return null;
    }
  }

  /// 获取远程播放列表，设置8秒的超时时间，并使用重试机制
  static Future<String?> _fetchM3uData(String url) async {
    try {
      return await _retryRequest<String>(
          () async => await HttpUtil().getRequest(url).timeout(
                Duration(seconds: 8),
              ));
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表', e, stackTrace);
      return null;
    }
  }

  /// 重试机制，最多重试 `retries` 次
  static Future<T?> _retryRequest<T>(Future<T?> Function() request,
      {int retries = 3,
      Duration retryDelay = const Duration(seconds: 2),
      Function(int attempt)? onRetry}) async {
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await request();
      } catch (e, stackTrace) {
        LogUtil.logError('请求失败，重试第 $attempt 次...', e, stackTrace);
        if (onRetry != null) {
          onRetry(attempt + 1);
        }
        if (attempt >= retries - 1) {
          return null;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }

  /// 合并多个 PlaylistModel，避免重复的播放地址
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
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
                  return;
                }

                // 判断是否已经合并过此 ID 的频道
                if (mergedChannelsById.containsKey(tvgId)) {
                  PlayModel existingChannel = mergedChannelsById[tvgId]!;

                  // 合并播放地址
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
                mergedPlaylist.playList![category]![groupTitle]![channelName] =
                    mergedChannelsById[tvgId]!;
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
  
  /// 获取本地缓存中的订阅数据列表、播放列表
  static Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v),
          defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取订阅数据列表失败', e, stackTrace);
      return [];
    }
  }

  static Future<String> _getCachedM3uData() async {
    try {
      return SpUtil.getString(Config.m3uCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存M3U数据失败', e, stackTrace);
      return '';
    }
  }

  static Future<void> saveCachedM3uData(String data) async {
    try {
      await SpUtil.putString(Config.m3uCacheKey, data);
    } catch (e, stackTrace) {
      LogUtil.logError('保存播放列表到本地缓存失败', e, stackTrace);
    }
  }

  /// 保存订阅模型数据到本地缓存
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    try {
      return await SpUtil.putObjectList(
              'local_m3u', models.map((e) => e.toJson()).toList()) ??
          false;
    } catch (e, stackTrace) {
      LogUtil.logError('保存订阅数据到本地缓存失败', e, stackTrace);
      return false;
    }
  }

  /// 判断链接是否为有效的直播链接
  static bool isLiveLink(String link) => _protocolRegex.hasMatch(link);

  /// 更新本地收藏列表中的频道播放地址
  static Future<void> updateFavoriteChannelsWithRemoteData(
      PlaylistModel remotePlaylist, PlaylistModel favoritePlaylist) async {
    // 更新收藏列表中的频道播放地址
    _updateFavoriteChannels(favoritePlaylist, remotePlaylist);
    // 保存更新后的收藏列表
    await saveFavoriteList(favoritePlaylist);
  }

  /// 更新收藏列表中的频道播放地址（仅当远程列表有更新）
  static void _updateFavoriteChannels(
      PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) {
    // 获取收藏分类中的频道
    final favoriteCategory = favoritePlaylist.playList?[Config.myFavoriteKey];
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
            _updateFavoriteChannel(
                favoriteCategory, remoteChannel.id!, remoteChannel);
            updatedTvgIds.add(remoteChannel.id!);
          }
        });
      });
    });
  }

  /// 更新"我的收藏"中单个频道的播放地址
  static void _updateFavoriteChannel(Map<String, Map<String, PlayModel>> favoriteCategory,
      String tvgId, PlayModel remoteChannel) {
    // 遍历"我的收藏"中的所有组和频道，找到对应的 id 进行更新
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        if (favoriteChannel.id == tvgId) {
          if (remoteChannel.urls != null && remoteChannel.urls!.isNotEmpty) {
            final validUrls =
                remoteChannel.urls!.where((url) => isLiveLink(url)).toList();
            if (validUrls.isNotEmpty) {
              favoriteChannel.urls = validUrls;
            }
          }
        }
      });
    });
  }
}
