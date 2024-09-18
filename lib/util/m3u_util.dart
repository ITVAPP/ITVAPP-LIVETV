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

  /// 统一错误处理方法，通过 try-catch 捕获并处理异常
  /// 在 catch 块中记录异常信息及堆栈信息
  static Future<M3uResult> _handleErrors(Future<M3uResult> Function() action) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      LogUtil.logError('操作失败', e, stackTrace);
      return M3uResult(errorMessage: '操作失败: $e');
    }
  }

  /// 获取本地缓存的M3U文件
  /// 如果缓存不存在，则尝试获取默认的M3U数据
  /// 在任何失败的情况下记录日志并返回错误信息
  static Future<M3uResult> getLocalM3uData() async {
    return _handleErrors(() async {
      final m3uDataString = await _getCachedM3uData();
      if (m3uDataString.isEmpty) {
        // 如果本地缓存没有数据，尝试获取默认M3U数据
        LogUtil.v('未找到本地M3U数据，尝试获取默认M3U数据...');
        return await getDefaultM3uData();
      }
      final parsedData = await _parseM3u(m3uDataString);  // 尝试解析M3U数据
      return M3uResult(data: parsedData);
    });
  }

  /// 获取默认的M3U文件，支持重试机制
  /// 在多种可能的失败场景中记录日志：网络失败、本地缓存失败等
  static Future<M3uResult> getDefaultM3uData({Function(int attempt)? onRetry}) async {
    return _handleErrors(() async {
      String m3uData = '';
      final models = await getLocalData();  // 获取本地存储的订阅数据

      if (models.isNotEmpty) {
        // 本地有订阅数据，优先使用本地数据
        final defaultModel = models.firstWhere((element) => element.selected ?? false, orElse: () => models.first);

        // 尝试通过重试机制从远程获取M3U数据
        final newRes = await _retryRequest<String>(() async {
          return await HttpUtil().getRequest(defaultModel.link == 'default'
              ? EnvUtil.videoDefaultChannelHost()
              : defaultModel.link!);
        }, onRetry: onRetry);

        if (newRes != null) {
          m3uData = newRes;
          await _saveCachedM3uData(m3uData);  // 保存到缓存中
        } else {
          m3uData = await _getCachedM3uData();  // 如果远程获取失败，尝试使用本地缓存
          if (m3uData.isEmpty) {
            LogUtil.logError('无法获取数据，本地缓存和网络请求都失败', 'm3uData为空');
            return M3uResult(errorMessage: '无法从本地缓存和网络中获取数据。');
          }
        }
      } else {
        // 没有本地数据，从网络获取
        m3uData = (await _retryRequest<String>(_fetchData, onRetry: onRetry)) ?? '';
        if (m3uData.isEmpty) {
          LogUtil.logError('网络数据获取失败', 'm3uData为空');
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

      // 尝试解析M3U数据
      final parsedData = await _parseM3u(m3uData);
      return M3uResult(data: parsedData);
    });
  }

  /// 封装的重试机制，最多重试 `retries` 次
  /// 每次失败时记录日志，并在达到最大重试次数时返回 null
  static Future<T?> _retryRequest<T>(
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

  /// 获取本地M3U数据
  /// 从本地缓存中获取订阅数据列表，如果失败会记录错误
  static Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地M3U数据失败', e, stackTrace);
      return [];
    }
  }

  /// 获取远程的默认M3U文件数据
  /// 通过 `HttpUtil` 发起请求获取数据，并在请求失败时记录日志
  static Future<String> _fetchData() async {
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
  /// 在解析过程中遇到问题时，记录相关错误
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
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
  /// 在请求超时或失败时记录日志
  static Future<String?> _fetchM3uData(String url) async {
    try {
      return await _retryRequest<String>(() async => await HttpUtil().getRequest(url).timeout(Duration(seconds: 8)));
    } catch (e, stackTrace) {
      LogUtil.logError('获取M3U数据失败', e, stackTrace);
      return null;
    }
  }

  /// 合并多个 PlaylistModel，避免重复的播放地址
  /// 合并过程中如果发生异常，记录日志
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

            // 合并同组同频道名的播放地址
            channels.forEach((channelName, channelModel) {
              if (mergedPlaylist.playList![category]![groupTitle]!.containsKey(channelName)) {
                // 如果频道已经存在，合并播放地址，确保不重复，保持顺序
                List<String> existingUrls = mergedPlaylist.playList![category]![groupTitle]![channelName]!.urls ?? [];
                List<String> newUrls = channelModel.urls ?? [];

                // 手动去重，保留原有顺序
                for (String url in newUrls) {
                  if (!existingUrls.contains(url)) {
                    existingUrls.add(url);
                  }
                }

                // 更新频道的播放地址列表
                mergedPlaylist.playList![category]![groupTitle]![channelName]!.urls = existingUrls;
              } else {
                // 如果频道不存在，直接添加
                mergedPlaylist.playList![category]![groupTitle]![channelName] = channelModel;
                mergedPlaylist.playList![category]![groupTitle]![channelName]!.urls =
                    channelModel.urls?.toList() ?? [];  // 直接使用原始列表
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

  /// 保存合并后的M3U数据到本地存储
  /// 如果保存失败，记录相关日志
  static Future<void> saveMergedM3u(PlaylistModel mergedPlaylist) async {
    try {
      String m3uString = _convertPlaylistToString(mergedPlaylist);
      await _saveCachedM3uData(m3uString);  // 保存到本地缓存
    } catch (e, stackTrace) {
      LogUtil.logError('保存合并后的M3U数据失败', e, stackTrace);
    }
  }

  /// 将 PlaylistModel 转换为 M3U 格式字符串
  /// 处理过程中出现任何错误都要记录日志
  static String _convertPlaylistToString(PlaylistModel playlist) {
    try {
      StringBuffer buffer = StringBuffer();

      playlist.playList?.forEach((category, groups) {
        groups.forEach((groupTitle, channels) {
          channels.forEach((channelName, playModel) {
            buffer.writeln('#EXTINF:-1 group-title="$groupTitle", $channelName');
            playModel.urls?.forEach((url) {
              if (url.isNotEmpty) {
                buffer.writeln(url);  // 写入每个播放地址
              }
            });
          });
        });
      });
      return buffer.toString();
    } catch (e, stackTrace) {
      LogUtil.logError('转换播放列表为M3U格式失败', e, stackTrace);
      return '';
    }
  }

  /// 获取本地缓存数据，如果缓存数据为空或读取失败，记录相关日志
  static Future<String> _getCachedM3uData() async {
    try {
      return SpUtil.getString('m3u_cache', defValue: '') ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地缓存M3U数据失败', e, stackTrace);
      return '';
    }
  }

  /// 保存数据到本地缓存，操作失败时记录日志
  static Future<void> _saveCachedM3uData(String data) async {
    try {
      await SpUtil.putString('m3u_cache', data);
    } catch (e, stackTrace) {
      LogUtil.logError('保存M3U数据到本地缓存失败', e, stackTrace);
    }
  }

  /// 保存订阅模型数据到本地缓存，保存失败时记录日志
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    try {
      return await SpUtil.putObjectList('local_m3u', models.map((e) => e.toJson()).toList()) ?? false;
    } catch (e, stackTrace) {
      LogUtil.logError('保存订阅数据到本地缓存失败', e, stackTrace);
      return false;
    }
  }

  /// 解析 M3U 文件并转换为 PlaylistModel 格式
  /// 在解析过程中记录可能出现的任何错误
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final lines = m3u.split('\n');
      final playListModel = PlaylistModel();
      playListModel.playList = <String, Map<String, Map<String, PlayModel>>>{};

      if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
        String tempGroupTitle = '';
        String tempChannelName = '';
        String tempCategory = '所有频道';

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

              Map<String, Map<String, PlayModel>> categoryMap = playListModel.playList![tempCategory] ?? {};
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
                playListModel.playList![tempCategory] = categoryMap;
                i += 1;
              } else if (isLiveLink(lines[i + 2])) {
                channel.urls ??= [];
                if (lines[i + 2].isNotEmpty) {
                  channel.urls!.add(lines[i + 2].toString());
                }
                groupMap[tempChannelName] = channel;
                categoryMap[tempGroupTitle] = groupMap;
                playListModel.playList![tempCategory] = categoryMap;
                i += 2;
              }
            }
          } else if (isLiveLink(line)) {
            playListModel.playList![tempCategory]![tempGroupTitle]![tempChannelName]!.urls ??= [];
            if (line.isNotEmpty) {
              playListModel.playList![tempCategory]![tempGroupTitle]![tempChannelName]!.urls!.add(line);
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

  /// 判断链接是否为直播链接
  static bool isLiveLink(String link) {
    final tLink = link.toLowerCase();
    return tLink.startsWith('http') || tLink.startsWith('r') || tLink.startsWith('p') || tLink.startsWith('s') || tLink.startsWith('w');
  }
}
