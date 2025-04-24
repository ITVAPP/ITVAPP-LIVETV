import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:async/async.dart' show LineSplitter;
import 'package:flutter/services.dart' show rootBundle;
import 'package:sp_util/sp_util.dart';
import 'package:opencc/opencc.dart';
import 'package:intl/intl.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/entity/subScribe_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

// 定义转换类型枚举
enum ConversionType {
  zhHans2Hant,
  zhHant2Hans,
}

// 转换类型工厂方法，用于创建 ZhConverter
ZhConverter? createConverter(ConversionType? type) {
  switch (type) {
    case ConversionType.zhHans2Hant:
      return ZhConverter(zhHans2Hant); // 简体转繁体
    case ConversionType.zhHant2Hans:
      return ZhConverter(zhHant2Hans); // 繁体转简体
    default:
      return null;
  }
}

/// 封装 M3U 数据返回结果
class M3uResult {
  final PlaylistModel? data; // 解析后的播放列表数据
  final String? errorMessage; // 错误信息
  final ErrorType? errorType; // 错误类型

  M3uResult({this.data, this.errorMessage, this.errorType});
}

/// 定义错误类型的枚举
enum ErrorType {
  networkError, // 网络错误
  parseError,   // 解析错误
  timeout,      // 超时错误
}

class M3uUtil {
  M3uUtil._();

  /// 工具方法：确保嵌套 Map 结构存在，若不存在则初始化
  static Map<String, Map<String, PlayModel>> ensureNestedMap(
      Map<String, Map<String, Map<String, PlayModel>>> playList, String category, String groupTitle) {
    playList[category] ??= <String, Map<String, PlayModel>>{};
    playList[category]![groupTitle] ??= <String, PlayModel>{};
    return playList[category]![groupTitle]!;
  }

  /// 获取远程播放列表，失败时加载本地 playlists.m3u 并合并收藏
  static Future<M3uResult> getDefaultM3uData({Function(int attempt, int remaining)? onRetry}) async {
    try {
      String m3uData = '';
      m3uData = (await _retryRequest<String>(
        _fetchData,
        onRetry: onRetry,
        maxTimeout: const Duration(seconds: 30),
      )) ?? '';

      PlaylistModel parsedData;
      if (m3uData.isEmpty) {
        LogUtil.logError('远程播放列表获取失败，加载本地 playlists.m3u', 'm3uData为空');
        final encryptedM3uData = await rootBundle.loadString('assets/playlists.m3u');
        final decryptedM3uData = _decodeEntireFile(encryptedM3uData);
        parsedData = await _parseM3u(decryptedM3uData);
        if (parsedData.playList == null) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      } else {
        parsedData = m3uData.contains('||') ? await fetchAndMergeM3uData(m3uData) ?? PlaylistModel() : await _parseM3u(m3uData);
        if (parsedData.playList == null) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      }

      LogUtil.i('解析播放列表: ${parsedData.playList}\n类型: ${parsedData.playList.runtimeType}');
      final favoritePlaylist = await getOrCreateFavoriteList();
      await updateFavoriteChannelsWithRemoteData(parsedData, PlaylistModel(playList: favoritePlaylist));
      parsedData.playList = _insertFavoritePlaylistFirst(parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>, PlaylistModel(playList: favoritePlaylist));
      LogUtil.i('合并收藏后播放列表类型: ${parsedData.playList.runtimeType}\n内容: ${parsedData.playList}');

      if (!m3uData.isEmpty) {
        await saveLocalData([SubScribeModel(time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full), link: 'default', selected: true)]);
      }
      return M3uResult(data: parsedData);
    } catch (e, stackTrace) {
      LogUtil.logError('获取播放列表出错', e, stackTrace);
      return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.networkError);
    }
  }

  /// 转换播放列表的指定中文字段（PlayModel.title 和 PlayModel.group）
  static PlaylistModel _convertPlaylistModel(PlaylistModel data, String conversionType) {
    try {
      // 映射字符串到枚举类型
      ConversionType? type;
      if (conversionType == 'zhHans2Hant') {
        type = ConversionType.zhHans2Hant;
      } else if (conversionType == 'zhHant2Hans') {
        type = ConversionType.zhHant2Hans;
      } else {
        LogUtil.i('无效的转换类型: $conversionType，跳过转换');
        return data; // 无效转换类型，回退到原始数据
      }

      // 检查 playList 是否为空或 null
      if (data.playList == null || data.playList!.isEmpty) {
        LogUtil.i('播放列表为空，无需转换');
        return data; // 空播放列表，回退到原始数据
      }

      // 延迟创建 ZhConverter
      final converter = createConverter(type);
      if (converter == null) {
        LogUtil.i('无法创建转换器，跳过转换');
        return data;
      }

      // 使用 map 方法转换三层嵌套结构
      final newPlayList = Map<String, Map<String, Map<String, PlayModel>>>.fromEntries(
        data.playList!.entries.map((categoryEntry) {
          final groupMap = categoryEntry.value;
          if (groupMap is! Map<String, Map<String, PlayModel>>) {
            return MapEntry(categoryEntry.key, <String, Map<String, PlayModel>>{});
          }

          final newGroupMap = Map<String, Map<String, PlayModel>>.fromEntries(
            groupMap.entries.map((groupEntry) {
              final channelMap = groupEntry.value;
              if (channelMap is! Map<String, PlayModel>) {
                return MapEntry(groupEntry.key, <String, PlayModel>{});
              }

              final newChannelMap = Map<String, PlayModel>.fromEntries(
                channelMap.entries.map((channelEntry) {
                  final playModel = channelEntry.value;
                  // 转换 title 和 group
                  final newTitle = playModel.title != null ? converter.convert(playModel.title!) : null;
                  final newGroup = playModel.group != null ? converter.convert(playModel.group!) : null;
                  // 创建新的 PlayModel
                  return MapEntry(
                    channelEntry.key,
                    playModel.copyWith(title: newTitle, group: newGroup),
                  );
                }),
              );
              return MapEntry(groupEntry.key, newChannelMap);
            }),
          );
          return MapEntry(categoryEntry.key, newGroupMap);
        }),
      );

      // 返回新的 PlaylistModel，保留 epgUrl
      return PlaylistModel(
        epgUrl: data.epgUrl,
        playList: newPlayList,
      );
    } catch (e, stackTrace) {
      LogUtil.logError('简繁体转换失败，回退到原始数据', e, stackTrace);
      return data; // 异常时回退原始数据
    }
  }

  /// 解密 M3U 文件内容（Base64 解码后 XOR 解密）
  static String _decodeEntireFile(String encryptedContent) {
    try {
      if (encryptedContent.isEmpty || !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encryptedContent)) {
        LogUtil.logError('解密失败', '无效的 Base64 字符串');
        return encryptedContent;
      }
      String xorStr = utf8.decode(base64Decode(encryptedContent));
      String decrypted = "";
      for (int i = 0; i < xorStr.length; i++) {
        decrypted += String.fromCharCode(xorStr.codeUnitAt(i) ^ Config.m3uXorKey.codeUnitAt(i % Config.m3uXorKey.length));
      }
      return decrypted;
    } catch (e, stackTrace) {
      LogUtil.logError('解密 M3U 文件失败', e, stackTrace);
      return encryptedContent;
    }
  }

  /// 获取或创建本地收藏列表
  static Future<Map<String, Map<String, Map<String, PlayModel>>>> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedFavoriteM3uData();
    if (favoriteData.isEmpty) {
      Map<String, Map<String, Map<String, PlayModel>>> favoritePlaylist = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
      LogUtil.i('创建收藏列表类型: ${favoritePlaylist.runtimeType}\n内容: $favoritePlaylist');
      return favoritePlaylist;
    } else {
      PlaylistModel favoritePlaylistModel = PlaylistModel.fromString(favoriteData);
      Map<String, Map<String, Map<String, PlayModel>>> favoritePlaylist = favoritePlaylistModel.playList?.cast<String, Map<String, Map<String, PlayModel>>>() ?? {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
      LogUtil.i('缓存收藏列表: $favoriteData\n解析后: $favoritePlaylist\n类型: ${favoritePlaylist.runtimeType}');
      return favoritePlaylist;
    }
  }

  /// 将收藏列表插入播放列表首位
  static Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
      Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist, PlaylistModel favoritePlaylist) {
    // 初始化结果 Map
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};
    originalPlaylist ??= {};

    // 优先插入收藏列表
    if (favoritePlaylist.playList != null && favoritePlaylist.playList!.containsKey(Config.myFavoriteKey)) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    } else if (originalPlaylist.containsKey(Config.myFavoriteKey)) {
      updatedPlaylist[Config.myFavoriteKey] = originalPlaylist[Config.myFavoriteKey]!;
    } else {
      updatedPlaylist[Config.myFavoriteKey] = <String, Map<String, PlayModel>>{};
    }

    // 添加非收藏的原始列表
    updatedPlaylist.addAll({
      for (var entry in originalPlaylist.entries)
        if (entry.key != Config.myFavoriteKey) entry.key: entry.value
    });

    return updatedPlaylist;
  }

  /// 保存收藏列表到本地缓存
  static Future<void> saveFavoriteList(PlaylistModel favoritePlaylist) async {
    await SpUtil.putString(Config.favoriteCacheKey, favoritePlaylist.toString());
  }

  /// 从本地缓存获取收藏列表数据
  static Future<String> _getCachedFavoriteM3uData() async {
    try {
      return SpUtil.getString(Config.favoriteCacheKey, defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地收藏列表失败', e, stackTrace);
      return '';
    }
  }

  /// 更新收藏列表中的播放地址并保存
  static Future<void> updateFavoriteChannelsWithRemoteData(PlaylistModel remotePlaylist, PlaylistModel favoritePlaylist) async {
    _updateFavoriteChannels(favoritePlaylist, remotePlaylist);
    await saveFavoriteList(favoritePlaylist);
  }

  /// 更新收藏列表中的频道播放地址
  static void _updateFavoriteChannels(PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) {
    final favoriteCategory = favoritePlaylist.playList?[Config.myFavoriteKey];
    if (favoriteCategory == null) return;
    final Map<String, List<String>> remoteIdToUrls = {};
    remotePlaylist.playList?.forEach((category, groups) {
      groups.forEach((groupTitle, channels) {
        channels.forEach((channelName, channelModel) {
          if (channelModel.id != null && channelModel.urls != null) remoteIdToUrls[channelModel.id!] = channelModel.urls!;
        });
      });
    });
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        if (favoriteChannel.id != null && remoteIdToUrls.containsKey(favoriteChannel.id!)) {
          final validUrls = remoteIdToUrls[favoriteChannel.id!]!.where((url) => isLiveLink(url)).toList();
          if (validUrls.isNotEmpty) favoriteChannel.urls = validUrls;
        }
      });
    });
  }

  /// 请求重试机制，支持超时和回调
  static Future<T?> _retryRequest<T>(Future<T?> Function() request,
      {int retries = 3, Duration retryDelay = const Duration(seconds: 2), Duration maxTimeout = const Duration(seconds: 30), Function(int attempt, int remaining)? onRetry}) async {
    final stopwatch = Stopwatch()..start();
    int attempt = 0;
    while (attempt < retries && stopwatch.elapsed <= maxTimeout) {
      try {
        Duration remainingTimeout = maxTimeout - stopwatch.elapsed;
        if (remainingTimeout.inMilliseconds <= 0) {
          LogUtil.logError('请求超时', '总时间已用尽');
          return null;
        }
        return await request().timeout(remainingTimeout);
      } catch (e, stackTrace) {
        attempt++;
        LogUtil.logError('请求失败，重试第 $attempt 次', e, stackTrace);
        if (onRetry != null) onRetry(attempt, retries - attempt);
        if (attempt >= retries || stopwatch.elapsed > maxTimeout) {
          LogUtil.logError('重试耗尽或超时', '尝试次数: $attempt, 已用时间: ${stopwatch.elapsed}');
          return null;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }

  /// 从本地缓存获取订阅数据
  static Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取订阅数据失败', e, stackTrace);
      return [];
    }
  }

  /// 获取远程播放列表数据
  static Future<String?> _fetchUrlData(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final String timeParam = DateFormat('yyyyMMddHH').format(DateTime.now());
      final urlWithTimeParam = '$url?time=$timeParam';
      final res = await HttpUtil().getRequest(urlWithTimeParam).timeout(timeout);
      return res ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      throw Exception('Network error: $e');
    }
  }

  /// 获取默认远程播放列表数据
  static Future<String?> _fetchData({String? url, Duration timeout = const Duration(seconds: 8)}) async {
    return _fetchUrlData(url ?? EnvUtil.videoDefaultChannelHost(), timeout: timeout);
  }

  /// 获取并合并多个 M3U 列表
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      List<String> urls = url.split('||');
      final results = await Future.wait(urls.map((u) => _fetchUrlData(u, timeout: const Duration(seconds: 8))));
      final playlists = <PlaylistModel>[];
      for (var m3uData in results) {
        if (m3uData != null) playlists.add(await _parseM3u(m3uData));
      }
      return playlists.isEmpty ? null : _mergePlaylists(playlists);
    } catch (e, stackTrace) {
      LogUtil.logError('合并播放列表失败', e, stackTrace);
      return null;
    }
  }

  /// 合并多个播放列表并去重
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    try {
      PlaylistModel mergedPlaylist = PlaylistModel()..playList = {};
      Map<String, PlayModel> mergedChannelsById = {};

      for (PlaylistModel playlist in playlists) {
        if (playlist.playList == null) continue;

        playlist.playList!.forEach((category, groups) {
          ensureNestedMap(mergedPlaylist.playList!, category, '');
          groups.forEach((groupTitle, channels) {
            final channelMap = ensureNestedMap(mergedPlaylist.playList!, category, groupTitle);
            channels.forEach((channelName, channelModel) {
              if (channelModel.id != null && channelModel.id!.isNotEmpty && channelModel.urls != null && channelModel.urls!.isNotEmpty) {
                String tvgId = channelModel.id!;
                if (mergedChannelsById.containsKey(tvgId)) {
                  LinkedHashSet<String> uniqueUrls = LinkedHashSet<String>.from(mergedChannelsById[tvgId]!.urls ?? []);
                  uniqueUrls.addAll(channelModel.urls ?? []);
                  mergedChannelsById[tvgId]!.urls = uniqueUrls.toList();
                } else {
                  mergedChannelsById[tvgId] = channelModel;
                }
                channelMap[channelName] = mergedChannelsById[tvgId]!;
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

  /// 解析 M3U 文件为 PlaylistModel
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final playListModel = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
      String currentCategory = Config.allChannelsKey;
      String tempGroupTitle = '';
      String tempChannelName = '';

      // 使用 LineSplitter 提高行分割效率
      final lines = LineSplitter.split(m3u).toList();
      if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.isEmpty) continue;

          if (line.startsWith('#EXTM3U')) {
            final params = line.replaceAll('"', '').split(' ');
            for (var param in params) {
              if (param.startsWith('x-tvg-url=')) {
                playListModel.epgUrl = param.substring(10);
              }
            }
          } else if (line.startsWith('#CATEGORY:')) {
            currentCategory = line.substring(10).trim().isNotEmpty ? line.substring(10).trim() : Config.allChannelsKey;
          } else if (line.startsWith('#EXTINF:')) {
            final match = extInfRegex.firstMatch(line);
            if (match == null || (match.group(2) ?? '').isEmpty) {
              LogUtil.logError('无效的 #EXTINF 行', '行内容: $line');
              continue;
            }

            final paramsStr = match.group(1) ?? '';
            final channelName = match.group(2)!;
            String groupTitle = S.current.defaultText;
            String tvgLogo = '';
            String tvgId = '';
            String tvgName = '';

            // 解析参数
            final params = paramRegex.allMatches(paramsStr);
            for (var param in params) {
              final key = param.group(1)!;
              final value = param.group(2)!;
              if (key == 'group-title') groupTitle = value;
              else if (key == 'tvg-logo') tvgLogo = value;
              else if (key == 'tvg-id') tvgId = value;
              else if (key == 'tvg-name') tvgName = value;
            }

            if (tvgId.isEmpty && tvgName.isNotEmpty) tvgId = tvgName;
            if (tvgId.isEmpty) {
              LogUtil.logError('缺少 tvg-id 或 tvg-name', '行内容: $line');
              continue;
            }

            tempGroupTitle = groupTitle;
            tempChannelName = channelName;

            // 使用 ensureNestedMap 初始化嵌套结构
            final channelMap = ensureNestedMap(playListModel.playList!, currentCategory, tempGroupTitle);
            channelMap[tempChannelName] ??= PlayModel(
              id: tvgId,
              group: tempGroupTitle,
              logo: tvgLogo,
              title: tempChannelName,
              urls: [],
            );

            // 检查后续行是否为直播链接
            if (i + 1 < lines.length && isLiveLink(lines[i + 1])) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty) {
                channelMap[tempChannelName]!.urls!.add(nextLine);
              }
              i += 1;
            } else if (i + 2 < lines.length && isLiveLink(lines[i + 2])) {
              final nextLine = lines[i + 2].trim();
              if (nextLine.isNotEmpty) {
                channelMap[tempChannelName]!.urls!.add(nextLine);
              }
              i += 2;
            }
          } else if (isLiveLink(line)) {
            final channelMap = ensureNestedMap(playListModel.playList!, currentCategory, tempGroupTitle);
            channelMap[tempChannelName] ??= PlayModel(
              id: '',
              group: tempGroupTitle,
              title: tempChannelName,
              urls: [],
            );
            channelMap[tempChannelName]!.urls!.add(line);
          }
        }
      } else {
        String tempGroup = S.current.defaultText;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          final lineList = line.split(',');
          if (lineList.length >= 2) {
            final groupTitle = lineList[0];
            final channelLink = lineList[1];
            if (isLiveLink(channelLink)) {
              final channelMap = ensureNestedMap(playListModel.playList!, tempGroup, groupTitle);
              channelMap[groupTitle] ??= PlayModel(
                group: tempGroup,
                id: groupTitle,
                title: groupTitle,
                urls: [],
              );
              if (channelLink.isNotEmpty) {
                channelMap[groupTitle]!.urls!.add(channelLink);
              }
            } else {
              tempGroup = groupTitle.isEmpty ? '${S.current.defaultText}${i + 1}' : groupTitle;
              ensureNestedMap(playListModel.playList!, tempGroup, tempGroup);
            }
          }
        }
      }

      LogUtil.i('解析完成，播放列表: ${playListModel.playList}');
      return playListModel;
    } catch (e, stackTrace) {
      LogUtil.logError('解析 M3U 文件失败', e, stackTrace);
      return PlaylistModel(playList: {Config.allChannelsKey: <String, Map<String, PlayModel>>{}});
    }
  }

  /// 判断链接是否为有效直播链接
  static bool isLiveLink(String link) {
    const protocols = ['http', 'https', 'rtmp', 'rtsp', 'mms', 'ftp'];
    return protocols.any((protocol) => link.toLowerCase().startsWith(protocol));
  }

  // 正则表达式优化：限制匹配范围，减少回溯
  static final RegExp extInfRegex = RegExp(r'#EXTINF:-1\s*([^,]*?)(?:,(.+))?$', multiLine: true);
  static final RegExp paramRegex = RegExp(r'(\w+[-?\w]*)=(?:"([^"]*)"|(\S+))', multiLine: true);
}
