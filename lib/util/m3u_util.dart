import 'dart:async';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';
import 'log_util.dart';

// 新增封装结果的类
class M3uResult {
  final PlaylistModel? data;
  final String? errorMessage;

  M3uResult({this.data, this.errorMessage});
}

class M3uUtil {
  M3uUtil._();

  // 获取本地缓存的m3u文件
  static Future<M3uResult> getLocalM3uData() async {
    try {
      final m3uData = SpUtil.getString('m3u_cache', defValue: '');
      if (m3uData?.isEmpty ?? true) {
        return M3uResult(errorMessage: 'No local M3U data found.');
      }

      final parsedData = await _parseM3u(m3uData!);
      return M3uResult(data: parsedData); // 成功时返回解析后的数据
    } catch (e) {
      LogUtil.e('Error loading local M3U data: $e');
      return M3uResult(errorMessage: 'Error loading local M3U data: $e');
    }
  }

  // 从远程获取默认的m3u文件并缓存
  static Future<M3uResult> getRemoteM3uData() async {
    try {
      String m3uData = await _fetchData(); // 从远程获取数据
      if (m3uData.isEmpty) {
        return M3uResult(errorMessage: 'Failed to fetch data from the network.');
      }

      // 缓存到本地
      await SpUtil.putString('m3u_cache', m3uData);

      final parsedData = await _parseM3u(m3uData);
      return M3uResult(data: parsedData); // 成功时返回解析后的数据
    } catch (e) {
      LogUtil.e('Error fetching remote M3U data: $e');
      return M3uResult(errorMessage: 'Error fetching remote M3U data: $e');
    }
  }

  // 获取默认的m3u文件，修改后的方法，保持原有功能
  static Future<M3uResult> getDefaultM3uData() async {
    String m3uData = '';
    final models = await getLocalData();

    try {
      if (models.isNotEmpty) {
        // 获取本地数据
        final defaultModel = models.firstWhere(
            (element) => element.selected == true,
            orElse: () => models.first);
        final newRes = await HttpUtil().getRequest(defaultModel.link == 'default'
            ? EnvUtil.videoDefaultChannelHost()
            : defaultModel.link!);

        if (newRes != null) {
          // 如果获取到新数据，保存到本地缓存
          LogUtil.v('已获取新数据::::::');
          m3uData = newRes;
          await SpUtil.putString('m3u_cache', m3uData);
        } else {
          // 如果无法获取网络数据，则尝试从本地缓存获取
          final oldRes = SpUtil.getString('m3u_cache', defValue: '');
          if (oldRes?.isNotEmpty ?? false) {
            LogUtil.v('已获取到历史保存的数据::::::');
            m3uData = oldRes ?? ''; // 如果 oldRes 是 null，使用空字符串
          } else {
            // 如果本地也没有缓存数据，返回错误信息
            LogUtil.e('无法获取数据，本地缓存和网络请求都失败');
            return M3uResult(errorMessage: 'Failed to load data from both cache and network.');
          }
        }

        if (m3uData.isEmpty) {
          return M3uResult(errorMessage: 'Received empty data.');
        }
      } else {
        // 如果本地没有数据，尝试从网络获取
        m3uData = await _fetchData();
        if (m3uData.isEmpty) {
          // 如果网络获取失败，返回错误信息
          LogUtil.e('网络数据获取失败');
          return M3uResult(errorMessage: 'Failed to fetch data from the network.');
        }
        // 成功获取数据后，保存到本地
        await saveLocalData([
          SubScribeModel(
              time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),
              link: 'default',
              selected: true)
        ]);
      }

      // 解析M3U数据
      final parsedData = await _parseM3u(m3uData);
      return M3uResult(data: parsedData); // 成功时返回数据
    } catch (e) {
      // 捕获所有异常并返回错误信息
      LogUtil.e('Error occurred while fetching M3U data: $e');
      return M3uResult(errorMessage: 'Error occurred: $e');
    }
  }

  // 获取本地m3u数据
  static Future<List<SubScribeModel>> getLocalData() async {
    Completer completer = Completer();
    List<SubScribeModel> m3uList = SpUtil.getObjList(
        'local_m3u', (v) => SubScribeModel.fromJson(v),
        defValue: <SubScribeModel>[])!;
    completer.complete(m3uList);
    final res = await completer.future;
    return res;
  }

  static Future<String> _fetchData() async {
    final defaultM3u = EnvUtil.videoDefaultChannelHost();
    final res = await HttpUtil().getRequest(defaultM3u);
    if (res == null) {
      LogUtil.e('网络数据获取失败');
      return "";  // 返回空字符串
    } else {
      return res;
    }
  }

  // 重试机制的封装，最多重试 3 次，每次间隔 2 秒
  static Future<T?> _retryRequest<T>(Future<T?> Function() request, {int retries = 3, Duration retryDelay = const Duration(seconds: 2)}) async {
    int attempt = 0;
    while (attempt < retries) {
      try {
        return await request();
      } on TimeoutException {
        LogUtil.e('请求超时，重试第 $attempt 次...');
      } on Exception catch (e) { // 捕获所有异常
        LogUtil.e('HTTP错误: ${e.toString()}');
        rethrow; // 对于 HTTP 错误，停止重试并抛出异常
      } catch (e) {
        attempt++;
        LogUtil.v('请求失败：$e，重试第 $attempt 次...');
        if (attempt >= retries) {
          LogUtil.e('请求失败超过最大次数 $retries 次，停止重试');
          rethrow;  // 达到最大重试次数，抛出异常
        }
        await Future.delayed(retryDelay);  // 等待重试
      }
    }
    return null;
  }

  // 获取并处理多个M3U列表的合并，解析每个 URL 返回的数据
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    List<String> urls = url.split('||');

    // 使用 Future.wait 并行处理多个M3U URL
    final results = await Future.wait(urls.map(_fetchM3uData));
    final playlists = <PlaylistModel>[];

    // 遍历每个返回的M3U数据并解析
    for (var m3uData in results) {
      if (m3uData != null) {
        final parsedPlaylist = await _parseM3u(m3uData);
        playlists.add(parsedPlaylist);
      }
    }

    if (playlists.isEmpty) {
      return null;
    }

    // 合并解析后的播放列表
    return _mergePlaylists(playlists);
  }

  // 获取M3U数据，设置8秒的超时时间，并使用重试机制
  static Future<String?> _fetchM3uData(String url) async {
    // 设置8秒超时时间
    return await _retryRequest(() async => await HttpUtil().getRequest(url).timeout(Duration(seconds: 8)) as String?);
  }

  // 合并多个PlaylistModel，避免重复的播放地址
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
            if (channelModel.urls?.isNotEmpty ?? false) {
              mergedPlaylist.playList![groupTitle]![channelName]!.urls = 
                mergedPlaylist.playList![groupTitle]![channelName]!.urls!
                .followedBy(channelModel.urls!).toSet().toList(); // 使用toSet去重
            }
          } else {
            // 如果频道不存在，直接添加
            if (channelModel.urls?.isNotEmpty ?? false) {
              mergedPlaylist.playList![groupTitle]![channelName] = channelModel;
              mergedPlaylist.playList![groupTitle]![channelName]!.urls = 
                mergedPlaylist.playList![groupTitle]![channelName]!.urls!.toSet().toList();
            }
          }
        });
      });
    }

    return mergedPlaylist;
  }

  // 保存合并后的M3U数据到本地存储
  static Future<void> saveMergedM3u(PlaylistModel mergedPlaylist) async {
    String m3uString = _convertPlaylistToString(mergedPlaylist);
    await SpUtil.putString('m3u_cache', m3uString); // 保存合并后的播放列表到本地缓存
  }

  // 将PlaylistModel转换为M3U格式字符串
  static String _convertPlaylistToString(PlaylistModel playlist) {
    StringBuffer buffer = StringBuffer();
    
    // 根据组名和频道名生成M3U格式内容
    playlist.playList?.forEach((groupTitle, channels) {
      channels.forEach((channelName, playModel) {
        buffer.writeln('#EXTINF:-1 group-title="$groupTitle", $channelName');
        playModel.urls?.forEach((url) {
          buffer.writeln(url); // 写入每个播放地址
        });
      });
    });
    return buffer.toString();
  }

  // 保存M3U数据到本地缓存
  static Future<bool> saveLocalData(List<SubScribeModel> models) async {
    final res = await SpUtil.putObjectList(
        'local_m3u', models.map((e) => e.toJson()).toList());
    return res ?? false;
  }

  // 解析M3U文件并转换为 PlaylistModel 格式
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    final lines = m3u.split('\n'); // 按行分割M3U内容
    final playListModel = PlaylistModel();
    playListModel.playList = <String, Map<String, PlayModel>>{};
    
    // 判断文件是否为标准M3U格式
    if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
      String tempGroupTitle = '';
      String tempChannelName = '';
      
      for (int i = 0; i < lines.length - 1; i++) {
        String line = lines[i];
        
        // 处理 #EXTM3U 开头的头部信息
        if (line.startsWith('#EXTM3U')) {
          List<String> params = line.replaceAll('"', '').split(' ');
          final tvgUrl = params.firstWhere(
              (element) => element.startsWith('x-tvg-url'),
              orElse: () => '');
          if (tvgUrl.isNotEmpty) {
            playListModel.epgUrl = tvgUrl.split('=').last; // 获取EPG URL
          }
        } else if (line.startsWith('#EXTINF:')) {
          if (line.startsWith('#EXTINF:-1,')) {
            line = line.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
          }
          final lineList = line.split(',');
          List<String> params = lineList.first.replaceAll('"', '').split(' ');
          final groupStr = params.firstWhere(
              (element) => element.startsWith('group-title='),
              orElse: () => 'group-title=${S.current.defaultText}');
          if (groupStr.isNotEmpty && groupStr.contains('=')) {
            tempGroupTitle = groupStr.split('=').last;
          }

          String tvgLogo = params.firstWhere(
              (element) => element.startsWith('tvg-logo='),
              orElse: () => '');
          if (tvgLogo.isNotEmpty && tvgLogo.contains('=')) {
            tvgLogo = tvgLogo.split('=').last;
          }

          String tvgId = params.firstWhere(
              (element) => element.startsWith('tvg-name='),
              orElse: () => '');
          if (tvgId.isEmpty) {
            tvgId = params.firstWhere(
                (element) => element.startsWith('tvg-id='),
                orElse: () => '');
          }
          if (tvgId.isNotEmpty && tvgId.contains('=')) {
            tvgId = tvgId.split('=').last;
          }

          if (groupStr.isNotEmpty) {
            tempGroupTitle = groupStr.split('=').last;
            tempChannelName = lineList.last;
            Map<String, PlayModel> group =
                playListModel.playList![tempGroupTitle] ?? {};
            PlayModel groupList = group[tempChannelName] ??
                PlayModel(
                    id: tvgId,
                    group: tempGroupTitle,
                    logo: tvgLogo,
                    title: tempChannelName,
                    urls: []);
            
            final lineNext = lines[i + 1];
            if (isLiveLink(lineNext)) {
              groupList.urls!.add(lineNext); // 添加播放地址
              group[tempChannelName] = groupList;
              playListModel.playList![tempGroupTitle] = group;
              i += 1;
            } else if (isLiveLink(lines[i + 2])) {
              groupList.urls!.add(lines[i + 2].toString());
              group[tempChannelName] = groupList;
              playListModel.playList![tempGroupTitle] = group;
              i += 2;
            }
          }
        } else if (isLiveLink(line)) {
          playListModel.playList![tempGroupTitle]![tempChannelName]!.urls!
              .add(line); // 添加额外的播放地址
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
            Map<String, PlayModel> group =
                playListModel.playList![tempGroup] ?? <String, PlayModel>{};
            final chanelList = group[groupTitle] ??
                PlayModel(
                    group: tempGroup,
                    id: groupTitle,
                    title: groupTitle,
                    urls: []);
            chanelList.urls!.add(channelLink); // 添加播放地址
            group[groupTitle] = chanelList;
            playListModel.playList![tempGroup] = group;
          } else {
            tempGroup = groupTitle == ''
                ? '${S.current.defaultText}${i + 1}'
                : groupTitle;
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
    if (tLink.startsWith('http') ||
        tLink.startsWith('r') ||
        tLink.startsWith('p') ||
        tLink.startsWith('s') ||
        tLink.startsWith('w')) {
      return true;
    }
    return false;
  }
}
