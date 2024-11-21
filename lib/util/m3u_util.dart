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

// 预编译正则表达式
final RegExp _m3uLinePattern = RegExp(r'^#EXTINF:-1\s*(.*)$');
final RegExp _groupTitlePattern = RegExp('group-title=["\']([^"\']*)["\']');
final RegExp _tvgIdPattern = RegExp('tvg-id=["\']([^"\']*)["\']');
final RegExp _tvgNamePattern = RegExp('tvg-name=["\']([^"\']*)["\']');
final RegExp _tvgLogoPattern = RegExp('tvg-logo=["\']([^"\']*)["\']');

// 处理行内容
String processLine(String originalLine) {
  if (originalLine.startsWith('#EXTINF:-1,')) {
    return originalLine.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
  }
  return originalLine;
}

// 预定义常量
const Map<String, String> _protocolMap = {
  'http': 'http',
  'https': 'https',
  'rtmp': 'rtmp', 
  'rtsp': 'rtsp',
  'mms': 'mms',
  'ftp': 'ftp'
};

/// 封装 M3U 数据
class M3uResult {
  final PlaylistModel? data;
  final String? errorMessage;

  M3uResult({this.data, this.errorMessage});
}

class M3uUtil {
 // 使用 late 延迟初始化
 static late final String _defaultM3u;
 static late final PlaylistModel _favoritePlaylist;
 
 M3uUtil._();

 /// 初始化
 static Future<void> init() async {
   _defaultM3u = EnvUtil.videoDefaultChannelHost();
   _favoritePlaylist = await getOrCreateFavoriteList();
 }

 /// 获取本地播放列表，如数据为空，则尝试获取远程播放列表
 static Future<M3uResult> getLocalM3uData() async {
   final buffer = StringBuffer();
   try {
     final m3uDataString = await _getCachedM3uData();
     if (m3uDataString.isEmpty) {
       return await getDefaultM3uData();
     }
     return M3uResult(data: PlaylistModel.fromString(m3uDataString));
   } catch (e, stackTrace) {
     buffer
       ..write('获取本地播放列表失败: ')
       ..write(e)
       ..write('\n堆栈: ')
       ..write(stackTrace);
     LogUtil.logError(buffer.toString(), e, stackTrace);
     return M3uResult(errorMessage: S.current.getm3udataerror);
   }
 }

 /// 获取远程播放列表
 static Future<M3uResult> getDefaultM3uData({Function(int attempt)? onRetry}) async {
   try {
     String m3uData = '';
     m3uData = (await _retryRequest<String>(_fetchData, onRetry: onRetry)) ?? '';

     if (m3uData.isEmpty) {
       LogUtil.logError('获取远程播放列表失败，尝试获取本地缓存数据', 'm3uData为空');
       final cachedData = PlaylistModel.fromString(await _getCachedM3uData());
       if (cachedData == null || cachedData.playList == null) {
         return M3uResult(errorMessage: S.current.getm3udataerror);
       }
       return M3uResult(data: cachedData);
     }

     PlaylistModel parsedData;

     if (m3uData.contains('||')) {
       parsedData = await fetchAndMergeM3uData(m3uData) ?? PlaylistModel();
     } else {
       parsedData = await _parseM3u(m3uData);
     }

     if (parsedData == null || parsedData.playList == null) {
       return M3uResult(errorMessage: S.current.getm3udataerror);
     }

     _logPlaylistInfo(parsedData, '解析后的');

     await updateFavoriteChannelsWithRemoteData(parsedData, _favoritePlaylist);

     parsedData.playList = _insertFavoritePlaylistFirst(
         parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>,
         _favoritePlaylist);

     await saveCachedM3uData(parsedData.toString());
     
     _logPlaylistInfo(parsedData, '保存后的');

     final now = DateTime.now();
     final formattedTime = DateUtil.formatDate(now, format: DateFormats.full);

     await saveLocalData([
       SubScribeModel(
         time: formattedTime,
         link: 'default',
         selected: true,
       ),
     ]);

     return M3uResult(data: parsedData);
   } catch (e, stackTrace) {
     LogUtil.logError('获取远程播放列表失败', e, stackTrace);
     return M3uResult(errorMessage: S.current.getm3udataerror);
   }
 }

 /// 获取远程播放列表
 static Future<String> _fetchData() async {
   try {
     final buffer = StringBuffer()
       ..write(_defaultM3u)
       ..write('?time=')
       ..write(DateFormat('yyyyMMddHH').format(DateTime.now()));
     
     final res = await HttpUtil().getRequest(buffer.toString());
     return res ?? '';
   } catch (e, stackTrace) {
     LogUtil.logError('获取远程播放列表失败', e, stackTrace);
     return '';
   }
 }
 
 /// 获取或创建本地的收藏列表
 static Future<PlaylistModel> getOrCreateFavoriteList() async {
   final favoriteData = await _getCachedFavoriteM3uData();

   if (favoriteData.isEmpty) {
     final favoritePlaylist = PlaylistModel(
       playList: {
         Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
       },
     );
     _logPlaylistInfo(favoritePlaylist, '创建的收藏');
     return favoritePlaylist;
   } else {
     final favoritePlaylist = PlaylistModel.fromString(favoriteData);
     final buffer = StringBuffer()
       ..write('缓存的收藏列表: ')
       ..write(favoriteData)
       ..writeln()
       ..write('解析后的收藏列表: ')
       ..write(favoritePlaylist)
       ..writeln()
       ..write('解析后的收藏列表类型: ')
       ..write(favoritePlaylist.playList.runtimeType);
     LogUtil.i(buffer.toString());
     return favoritePlaylist;
   }
 }

 /// 将收藏列表插入为播放列表的第一个分类
 static Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
     Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist,
     PlaylistModel favoritePlaylist) {
   final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};

   // 优先添加收藏列表
   if (favoritePlaylist.playList?[Config.myFavoriteKey] != null) {
     updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
   } else if (originalPlaylist?[Config.myFavoriteKey] != null) {
     updatedPlaylist[Config.myFavoriteKey] = originalPlaylist![Config.myFavoriteKey]!;
   }

   // 添加原播放列表中的其他分类
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

 /// 更新本地收藏列表中的频道播放地址
 static Future<void> updateFavoriteChannelsWithRemoteData(
     PlaylistModel remotePlaylist, PlaylistModel favoritePlaylist) async {
   _updateFavoriteChannels(favoritePlaylist, remotePlaylist);
   await saveFavoriteList(favoritePlaylist);
 }

 /// 更新收藏列表中的频道播放地址（仅当远程列表有更新）
 static void _updateFavoriteChannels(
     PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) {
   final favoriteCategory = favoritePlaylist.playList?[Config.myFavoriteKey];
   if (favoriteCategory == null) return;

   final Set<String> updatedTvgIds = {};

   remotePlaylist.playList?.forEach((category, groups) {
     groups.forEach((groupTitle, channels) {
       channels.forEach((channelName, remoteChannel) {
         if (remoteChannel.id != null && remoteChannel.id!.isNotEmpty) {
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

 /// 从本地缓存中获取订阅数据列表
 static Future<List<SubScribeModel>> getLocalData() async {
   try {
     return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v),
         defValue: <SubScribeModel>[])!;
   } catch (e, stackTrace) {
     LogUtil.logError('获取订阅数据列表失败', e, stackTrace);
     return [];
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

 /// 使用 StringBuffer 优化日志输出
 static void _logPlaylistInfo(PlaylistModel parsedData, String prefix) {
   final buffer = StringBuffer()
     ..write(prefix)
     ..write('播放列表类型: ')
     ..write(parsedData.playList.runtimeType)
     ..write('\n播放列表内容: ')
     ..write(parsedData.playList);
   LogUtil.i(buffer.toString());
 }
 
 /// 合并多个 PlaylistModel，避免重复的播放地址
 static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
   try {
     final mergedPlaylist = PlaylistModel();
     mergedPlaylist.playList = {};

     // 使用 Map 缓存已合并的频道
     final Map<String, PlayModel> mergedChannelsById = {};

     for (final playlist in playlists) {
       playlist.playList?.forEach((category, groups) {
         mergedPlaylist.playList ??= {};
         mergedPlaylist.playList![category] ??= {};
         
         groups.forEach((groupTitle, channels) {
           mergedPlaylist.playList![category]![groupTitle] ??= {};

           channels.forEach((channelName, channelModel) {
             if (channelModel.id != null && channelModel.id!.isNotEmpty) {
               final tvgId = channelModel.id!;

               if (channelModel.urls == null || channelModel.urls!.isEmpty) {
                 return;
               }

               if (mergedChannelsById.containsKey(tvgId)) {
                 final existingChannel = mergedChannelsById[tvgId]!;

                 // 使用 Set 优化合并去重
                 final existingUrls = existingChannel.urls?.toSet() ?? {};
                 final newUrls = channelModel.urls?.toSet() ?? {};
                 existingUrls.addAll(newUrls);

                 existingChannel.urls = existingUrls.toList();
                 mergedChannelsById[tvgId] = existingChannel;
               } else {
                 mergedChannelsById[tvgId] = channelModel;
               }

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

 /// 获取本地缓存播放列表
 static Future<String> _getCachedM3uData() async {
   try {
     return SpUtil.getString(Config.m3uCacheKey, defValue: '') ?? '';
   } catch (e, stackTrace) {
     LogUtil.logError('获取本地缓存M3U数据失败', e, stackTrace);
     return '';
   }
 }

 /// 保存播放列表到本地缓存
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
 static bool isLiveLink(String link) {
   final lowerLink = link.toLowerCase();
   return _protocolMap.values.any((protocol) => lowerLink.startsWith(protocol));
 }
 
 /// 解析 M3U 文件并转换为 PlaylistModel 格式
 static Future<PlaylistModel> _parseM3u(String m3u) async {
   try {
     final lines = m3u.split(RegExp(r'\r?\n'));
     final playListModel = PlaylistModel();
     playListModel.playList = <String, Map<String, Map<String, PlayModel>>>{};

     // 使用局部变量缓存频繁访问的值
     String currentCategory = Config.allChannelsKey;
     bool hasCategory = false;

     if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
       String tempGroupTitle = '';
       String tempChannelName = '';
       final buffer = StringBuffer();

       for (int i = 0; i < lines.length; i++) {
         final line = lines[i];

         if (line.startsWith('#EXTM3U')) {
           final params = line.replaceAll('"', '').split(' ');
           final tvgUrl = params
               .firstWhere((element) => element.startsWith('x-tvg-url'),
                   orElse: () => '')
               .split('=')
               .last;
           if (tvgUrl.isNotEmpty) {
             playListModel.epgUrl = tvgUrl;
           }
         } else if (line.startsWith('#CATEGORY:')) {
           currentCategory = line.replaceFirst('#CATEGORY:', '').trim();
           hasCategory = true;
           if (currentCategory.isEmpty) {
             currentCategory = Config.allChannelsKey;
           }
         } else if (_m3uLinePattern.hasMatch(line)) {
           var processedLine = line;
           if (processedLine.startsWith('#EXTINF:-1,')) {
              processedLine = processedLine.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
           }
           final lineList = processedLine.split(',');
           final params = lineList.first.replaceAll('"', '').split(' ');

           final groupMatch = _groupTitlePattern.firstMatch(line);
           tempGroupTitle = groupMatch?.group(1) ?? S.current.defaultText;

           final tvgLogoMatch = _tvgLogoPattern.firstMatch(line);
           final tvgLogo = tvgLogoMatch?.group(1) ?? '';

           var tvgId = '';
           final tvgIdMatch = _tvgIdPattern.firstMatch(line);
           final tvgNameMatch = _tvgNamePattern.firstMatch(line);
          
           if (tvgIdMatch != null) {
             tvgId = tvgIdMatch.group(1)!;
           } else if (tvgNameMatch != null) {
             tvgId = tvgNameMatch.group(1)!;
           }

           if (tvgId.isEmpty) {
             continue;
           }

           if (!hasCategory) {
             currentCategory = Config.allChannelsKey;
           }

           tempChannelName = lineList.last;

           // 使用局部变量缓存Map操作
           final categoryMap = playListModel.playList?[currentCategory] ?? {};
           final groupMap = categoryMap[tempGroupTitle] ?? {};
           final channel = groupMap[tempChannelName] ??
               PlayModel(
                   id: tvgId,
                   group: tempGroupTitle,
                   logo: tvgLogo,
                   title: tempChannelName,
                   urls: []);

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
         } else if (isLiveLink(line)) {
           if (line.isNotEmpty) {
             playListModel.playList?[currentCategory]?[tempGroupTitle]
                     ?[tempChannelName]
                 ?.urls ??= [];
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
             // 使用局部变量缓存Map操作
             final categoryMap = playListModel.playList?[tempGroup] ?? {};
             final groupMap = categoryMap[groupTitle] ?? {};
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
     LogUtil.logError('解析M3U文件失败 ', e, stackTrace);
     return PlaylistModel();
   }
 }
}
