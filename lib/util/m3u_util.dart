import 'dart:async';
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

  // 统一错误处理方法
  static Future<M3uResult> _handleErrors(Future<M3uResult> Function() action) async {
    try {
      return await action();
    } catch (e) {
      LogUtil.e('操作失败: $e');
      return M3uResult(errorMessage: '操作失败: $e');
    }
  }

  // 获取本地缓存的M3U文件
  static Future<M3uResult> getLocalM3uData() async {
    return _handleErrors(() async {
      final m3uData = _getCachedM3uData();  // 使用缓存获取方法
      if (m3uData.isEmpty) {
        // 如果本地缓存中没有M3U数据，则获取默认M3U数据
        LogUtil.v('未找到本地M3U数据，尝试获取默认M3U数据...');
        return await getDefaultM3uData();
      }
      final parsedData = await _parseM3u(m3uData);  // 解析M3U数据
      return M3uResult(data: parsedData);
    });
  }

  // 获取默认的M3U文件
  static Future<M3uResult> getDefaultM3uData() async {
    return _handleErrors(() async {
      String m3uData = '';
      final models = await getLocalData();  // 获取本地存储的数据

      if (models.isNotEmpty) {
        // 本地有订阅数据，优先使用本地数据
        final defaultModel = models.firstWhere((element) => element.selected, orElse: () => models.first);

        // 使用重试机制从远程获取M3U数据
        final newRes = await _retryRequest<String>(() async {
          return await HttpUtil().getRequest(defaultModel.link == 'default'
              ? EnvUtil.videoDefaultChannelHost()
              : defaultModel.link!);
        });

        if (newRes != null) {
          m3uData = newRes;
          await _saveCachedM3uData(m3uData);  // 保存到缓存
        } else {
          m3uData = await _getCachedM3uData();  // 尝试使用本地缓存数据
          if (m3uData.isEmpty) {
            LogUtil.e('无法获取数据，本地缓存和网络请求都失败');
            return M3uResult(errorMessage: '无法从本地缓存和网络中获取数据。');
          }
        }
      } else {
        // 没有本地数据，直接从网络获取
        m3uData = (await _retryRequest<String>(_fetchData)) ?? '';
        if (m3uData.isEmpty) {
          LogUtil.e('网络数据获取失败');
          return M3uResult(errorMessage: '从网络获取数据失败。');
        }

        // 保存新订阅数据到本地
        await saveLocalData([
          SubScribeModel(
              time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),
              link: 'default',
              selected: true)
        ]);
      }

      // 解析M3U数据
      final parsedData = await _parseM3u(m3uData);
      return M3uResult(data: parsedData);
    });
  }

  // 获取本地M3U数据
  static Future<List<SubScribeModel>> getLocalData() async {
    return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
  }

  // 获取远程的默认M3U文件数据
  static Future<String> _fetchData() async {
    final defaultM3u = EnvUtil.videoDefaultChannelHost();
    final res = await HttpUtil().getRequest(defaultM3u);
    return res ?? '';  // 返回空字符串表示获取失败
  }

  // 重试机制封装，最多重试3次，每次间隔2秒
  static Future<T?> _retryRequest<T>(Future<T?> Function() request, {int retries = 3, Duration retryDelay = const Duration(seconds: 2)}) async {
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await request();
      } catch (e) {
        LogUtil.e('请求失败：$e，重试第 $attempt 次...');
        if (attempt >= retries - 1) {
          return null;  // 超过重试次数，返回null
        }
        await Future.delayed(retryDelay);  // 重试延时
      }
    }
    return null;
  }

  // 获取并处理多个M3U列表的合并，解析每个 URL 返回的数据
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
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
  }

  // 获取M3U数据，设置8秒的超时时间，并使用重试机制
  static Future<String?> _fetchM3uData(String url) async {
    return await _retryRequest<String>(() async => await HttpUtil().getRequest(url).timeout(Duration(seconds: 8)));
  }

  // 合并多个 PlaylistModel，避免重复的播放地址
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    PlaylistModel mergedPlaylist = PlaylistModel();
    mergedPlaylist.playList = {};

    for (PlaylistModel playlist in playlists) {
      playlist.playList?.forEach((groupTitle, channels) {
        mergedPlaylist.playList ??= {};
        mergedPlaylist.playList![groupTitle] ??= {};

        // 合并同组同频道名的播放地址
        channels.forEach((channelName, channelModel) {
          if (mergedPlaylist.playList![groupTitle]!.containsKey(channelName)) {
            // 如果频道已经存在，合并播放地址，并去重
            mergedPlaylist.playList![groupTitle]![channelName]!.urls = 
                mergedPlaylist.playList![groupTitle]![channelName]!.urls!
                    .followedBy(channelModel.urls ?? []).toSet().toList();
          } else {
            // 如果频道不存在，直接添加
            mergedPlaylist.playList![groupTitle]![channelName] = channelModel;
            mergedPlaylist.playList![groupTitle]![channelName]!.urls =
                channelModel.urls?.toSet().toList() ?? [];
          }
        });
      });
    }

    return mergedPlaylist;
  }

  // 保存合并后的M3U数据到本地存储
  static Future<void> saveMergedM3u(PlaylistModel mergedPlaylist) async {
    String m3uString = _convertPlaylistToString(mergedPlaylist);
    await _saveCachedM3uData(m3uString);  // 保存到本地缓存
  }

  // 将 PlaylistModel 转换为 M3U 格式字符串
  static String _convertPlaylistToString(PlaylistModel playlist) {
    StringBuffer buffer = StringBuffer();

    playlist.playList?.forEach((groupTitle, channels) {
      channels.forEach((channelName, playModel) {
        buffer.writeln('#EXTINF:-1 group-title="$groupTitle", $channelName');
        playModel.urls?.forEach((url) {
          if (url.isNotEmpty) {
            buffer.writeln(url);  // 写入每个播放地址
          }
        });
      });
    });
    return buffer.toString();
  }

  // 获取本地缓存数据
  static Future<String> _getCachedM3uData() async {
    return SpUtil.getString('m3u_cache', defValue: '') ?? '';
  }

  // 保存数据到本地缓存
  static Future<void> _saveCachedM3uData(String data) async {
    await SpUtil.putString('m3u_cache', data);
  }

  // 保存M3U数据到本地缓存
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    return await SpUtil.putObjectList('local_m3u', models.map((e) => e.toJson()).toList()) ?? false;
  }

  // 解析 M3U 文件并转换为 PlaylistModel 格式
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    final lines = m3u.split('\n');
    final playListModel = PlaylistModel();
    playListModel.playList = <String, Map<String, PlayModel>>{};

    if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
      String tempGroupTitle = '';
      String tempChannelName = '';

      for (int i = 0; i < lines.length - 1; i++) {
        String line = lines[i];

        if (line.startsWith('#EXTM3U')) {
          List<String> params = line.replaceAll('"', '').split(' ');
          final tvgUrl = params.firstWhere((element) => element.startsWith('x-tvg-url'), orElse: () => '');
          if (tvgUrl.isNotEmpty) {
            playListModel.epgUrl = tvgUrl.split('=').last;  // 获取EPG URL
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
            Map<String, PlayModel> group = playListModel.playList![tempGroupTitle] ?? {};
            PlayModel groupList = group[tempChannelName] ?? PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

            final lineNext = lines[i + 1];
            if (isLiveLink(lineNext)) {
              groupList.urls ??= [];
              if (lineNext.isNotEmpty) {
                groupList.urls!.add(lineNext);
              }
              group[tempChannelName] = groupList;
              playListModel.playList![tempGroupTitle] = group;
              i += 1;
            } else if (isLiveLink(lines[i + 2])) {
              groupList.urls ??= [];
              if (lines[i + 2].isNotEmpty) {
                groupList.urls!.add(lines[i + 2].toString());
              }
              group[tempChannelName] = groupList;
              playListModel.playList![tempGroupTitle] = group;
              i += 2;
            }
          }
        } else if (isLiveLink(line)) {
          playListModel.playList![tempGroupTitle]![tempChannelName]!.urls ??= [];
          if (line.isNotEmpty) {
            playListModel.playList![tempGroupTitle]![tempChannelName]!.urls!.add(line);
          }
        }
      }
    } else {
      // 处理非标准M3U文件
      String tempGroup = S.current.defaultText;
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i];
        final lineList = line.split(',');
        if (lineList.length >= 2) {
          final groupTitle = lineList[0];
          final channelLink = lineList[1];
          if (isLiveLink(channelLink)) {
            Map<String, PlayModel> group = playListModel.playList![tempGroup] ?? <String, PlayModel>{};
            final chanelList = group[groupTitle] ?? PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
            chanelList.urls ??= [];
            if (channelLink.isNotEmpty) {
              chanelList.urls!.add(channelLink);
            }
            group[groupTitle] = chanelList;
            playListModel.playList![tempGroup] = group;
          } else {
            tempGroup = groupTitle == '' ? '${S.current.defaultText}${i + 1}' : groupTitle;
            if (playListModel.playList![tempGroup] == null) {
              playListModel.playList![tempGroup] = <String, PlayModel>{};
            }
          }
        }
      }
    }
    return playListModel;
  }

  // 判断链接是否为直播链接
  static bool isLiveLink(String link) {
    final tLink = link.toLowerCase();
    return tLink.startsWith('http') || tLink.startsWith('r') || tLink.startsWith('p') || tLink.startsWith('s') || tLink.startsWith('w');
  }
}
