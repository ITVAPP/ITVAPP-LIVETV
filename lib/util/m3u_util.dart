import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sp_util/sp_util.dart';
import 'package:intl/intl.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/entity/subScribe_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

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
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};
    originalPlaylist ??= {};
    if (originalPlaylist[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    } else if (favoritePlaylist.playList?[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    } else {
      updatedPlaylist[Config.myFavoriteKey] = <String, Map<String, PlayModel>>{};
    }
    originalPlaylist.forEach((key, value) {
      if (key != Config.myFavoriteKey) updatedPlaylist[key] = value;
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
        playlist.playList?.forEach((category, groups) {
          mergedPlaylist.playList![category] ??= {};
          groups.forEach((groupTitle, channels) {
            mergedPlaylist.playList![category]![groupTitle] ??= {};
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

  /// 保存订阅数据到本地缓存
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    try {
      return await SpUtil.putObjectList('local_m3u', models.map((e) => e.toJson()).toList()) ?? false;
    } catch (e, stackTrace) {
      LogUtil.logError('保存订阅数据失败', e, stackTrace);
      return false;
    }
  }

  static final RegExp extInfRegex = RegExp(r'#EXTINF:-1\s*(?:([^,]*?),)?(.+)', multiLine: true);
  static final RegExp paramRegex = RegExp("(\\w+[-\\w]*)=[\"']?([^\"'\\s]+)[\"']?");

  /// 解析 M3U 文件为 PlaylistModel
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final lines = m3u.split(RegExp(r'\r?\n'));
      final playListModel = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
      String currentCategory = Config.allChannelsKey;
      String tempGroupTitle = '';
      String tempChannelName = '';

      if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.isEmpty) continue;
          if (line.startsWith('#EXTM3U')) {
            final params = line.replaceAll('"', '').split(' ');
            for (var param in params) {
              if (param.startsWith('x-tvg-url=')) playListModel.epgUrl = param.substring(10);
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

            // 使用改进的正则表达式解析参数
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
            playListModel.playList![currentCategory] ??= <String, Map<String, PlayModel>>{};
            playListModel.playList![currentCategory]![tempGroupTitle] ??= <String, PlayModel>{};
            PlayModel channel = playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName] ??
                PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

            if (i + 1 < lines.length && isLiveLink(lines[i + 1])) {
              channel.urls ??= [];
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty) channel.urls!.add(nextLine);
              playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName] = channel;
              i += 1;
            } else if (i + 2 < lines.length && isLiveLink(lines[i + 2])) {
              channel.urls ??= [];
              final nextLine = lines[i + 2].trim();
              if (nextLine.isNotEmpty) channel.urls!.add(nextLine);
              playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName] = channel;
              i += 2;
            }
          } else if (isLiveLink(line)) {
            playListModel.playList![currentCategory] ??= <String, Map<String, PlayModel>>{};
            playListModel.playList![currentCategory]![tempGroupTitle] ??= <String, Map<String, PlayModel>>{};
            playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName] ??=
                PlayModel(id: '', group: tempGroupTitle, title: tempChannelName, urls: []);
            playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls ??= [];
            playListModel.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls!.add(line);
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
              playListModel.playList![tempGroup] ??= <String, Map<String, PlayModel>>{};
              playListModel.playList![tempGroup]![groupTitle] ??= <String, PlayModel>{};
              final channel = playListModel.playList![tempGroup]![groupTitle]![groupTitle] ??
                  PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
              channel.urls ??= [];
              if (channelLink.isNotEmpty) channel.urls!.add(channelLink);
              playListModel.playList![tempGroup]![groupTitle]![groupTitle] = channel;
            } else {
              tempGroup = groupTitle.isEmpty ? '${S.current.defaultText}${i + 1}' : groupTitle;
              playListModel.playList![tempGroup] ??= <String, Map<String, PlayModel>>{};
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
}
