import 'dart:async';
import 'dart:convert';
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
  final PlaylistModel? data;
  final String? errorMessage;
  final ErrorType? errorType;

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

  /// 获取远程播放列表，失败时使用 assets 中的 playlists.m3u，并与收藏列表合并
  static Future<M3uResult> getDefaultM3uData({Function(int attempt, int remaining)? onRetry}) async {
    try {
      String m3uData = '';

      // 尝试通过重试机制获取远程播放列表
      m3uData = (await _retryRequest<String>(
        _fetchData,
        onRetry: onRetry,
        maxTimeout: const Duration(seconds: 30), // 添加最大超时限制
      )) ?? '';

      PlaylistModel parsedData;

      if (m3uData.isEmpty) {
        LogUtil.logError('获取远程播放列表失败，尝试加载 assets 中的 playlists.m3u', 'm3uData为空');

        // 从 assets 中加载 playlists.m3u
        final String assetM3uData = await rootBundle.loadString('assets/playlists.m3u');
        parsedData = await _parseM3u(assetM3uData);

        if (parsedData.playList == null) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      } else {
        // 判断 m3uData 是否包含多个 URL（通过 || 分隔符识别）
        if (m3uData.contains('||')) {
          // 如果有多个 URL，调用 fetchAndMergeM3uData 进行获取和合并
          parsedData = await fetchAndMergeM3uData(m3uData) ?? PlaylistModel();
        } else {
          // 单一 URL 的情况，直接解析 M3U 数据
          parsedData = await _parseM3u(m3uData);
        }

        if (parsedData.playList == null) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      }

      LogUtil.i('解析后的播放列表内容: ${parsedData.playList}\n解析后的播放列表类型: ${parsedData.playList.runtimeType}');

      // 获取或创建本地收藏列表
      final favoritePlaylist = await getOrCreateFavoriteList();

      // 使用远程数据更新收藏列表中的频道播放地址
      await updateFavoriteChannelsWithRemoteData(parsedData, favoritePlaylist);

      // 将收藏列表加入到播放列表中，并设置为第一个分类
      parsedData.playList = _insertFavoritePlaylistFirst(
          parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>,
          favoritePlaylist);
      
      LogUtil.i('合并收藏后的播放列表类型: ${parsedData.playList.runtimeType}\n合并收藏后的播放列表内容: ${parsedData.playList}');

      // 保存新订阅数据到本地（仅在远程获取成功时更新订阅时间）
      if (!m3uData.isEmpty) {
        await saveLocalData([
          SubScribeModel(
            time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),
            link: 'default',
            selected: true,
          ),
        ]);
      }

      return M3uResult(data: parsedData);
    } catch (e, stackTrace) {
      LogUtil.logError('获取播放列表时出错', e, stackTrace);
      return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.networkError);
    }
  }

  /// 获取或创建本地的收藏列表
  static Future<PlaylistModel> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedFavoriteM3uData();

    if (favoriteData.isEmpty) {
      // 如果没有缓存数据，创建一个新的空收藏列表
      PlaylistModel favoritePlaylist = PlaylistModel(
        playList: {
          Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
        },
      );
      LogUtil.i('创建的收藏列表类型: ${favoritePlaylist.playList.runtimeType}\n创建的收藏列表: ${favoritePlaylist.playList}');
      return favoritePlaylist;
    } else {
      // 如果本地已有缓存数据，将其转换为 PlaylistModel 对象
      PlaylistModel favoritePlaylist = PlaylistModel.fromString(favoriteData);
      favoritePlaylist.playList ??= {};
      LogUtil.i('缓存的收藏列表: ${favoriteData}\n解析后的收藏列表: ${favoritePlaylist}\n解析后的收藏列表类型: ${favoritePlaylist.playList.runtimeType}');
      return favoritePlaylist;
    }
  }

  /// 将收藏列表插入为播放列表的第一个分类
  /// 修改说明：将返回类型从 `Map` 改为 `Map<String, Map<String, Map<String, PlayModel>>>`，并指定输入参数类型，
  /// 以匹配 `PlaylistModel.playList` 的类型，避免类型不匹配错误
  static Map<String, Map<String, Map<String, PlayModel>>> _insertFavoritePlaylistFirst(
      Map<String, Map<String, Map<String, PlayModel>>>? originalPlaylist,
      PlaylistModel favoritePlaylist) {
    final updatedPlaylist = <String, Map<String, Map<String, PlayModel>>>{};

    originalPlaylist ??= {};
    // 如果原始播放列表中已有同名的收藏列表，使用本地收藏列表替换它
    if (originalPlaylist[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    }
    // 检查并确保即使为空也能插入收藏分类
    else if (favoritePlaylist.playList?[Config.myFavoriteKey] != null) {
      updatedPlaylist[Config.myFavoriteKey] = favoritePlaylist.playList![Config.myFavoriteKey]!;
    } else {
      updatedPlaylist[Config.myFavoriteKey] = <String, Map<String, PlayModel>>{}; 
    }

    // 将其余分类添加到新播放列表中（除收藏分类外的所有分类）
    originalPlaylist.forEach((key, value) {
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

  /// 从本地缓存中获取收藏列表数据
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
    // 更新收藏列表中的频道播放地址
    _updateFavoriteChannels(favoritePlaylist, remotePlaylist);
    // 保存更新后的收藏列表到本地缓存
    await saveFavoriteList(favoritePlaylist);
  }

  /// 更新收藏列表中的频道播放地址
  static void _updateFavoriteChannels(PlaylistModel favoritePlaylist, PlaylistModel remotePlaylist) {
    final favoriteCategory = favoritePlaylist.playList?[Config.myFavoriteKey]; 
    if (favoriteCategory == null) return;

    // 构建远程播放列表的 ID 到 URL 的映射表，提高查找效率
    final Map<String, List<String>> remoteIdToUrls = {};
    remotePlaylist.playList?.forEach((category, groups) {
      groups.forEach((groupTitle, channels) {
        channels.forEach((channelName, channelModel) {
          if (channelModel.id != null && channelModel.urls != null) {
            remoteIdToUrls[channelModel.id!] = channelModel.urls!;
          }
        });
      });
    });

    // 遍历收藏列表中的频道，更新其播放地址
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        if (favoriteChannel.id != null && remoteIdToUrls.containsKey(favoriteChannel.id!)) {
          // 过滤出有效的直播链接
          final validUrls = remoteIdToUrls[favoriteChannel.id!]!
              .where((url) => isLiveLink(url))
              .toList();
          // 只有当有有效链接时才更新
          if (validUrls.isNotEmpty) {
            favoriteChannel.urls = validUrls;
          }
        }
      });
    });
  }

  /// 请求重试机制，支持最大超时限制
  /// [retries] 最大重试次数，默认为3次
  /// [retryDelay] 重试间隔时间，默认为2秒
  /// [maxTimeout] 最大总超时时间，默认为30秒
  /// [onRetry] 重试时的回调函数，传入当前尝试次数和剩余次数
  static Future<T?> _retryRequest<T>(Future<T?> Function() request,
      {int retries = 3,
      Duration retryDelay = const Duration(seconds: 2),
      Duration maxTimeout = const Duration(seconds: 30),
      Function(int attempt, int remaining)? onRetry}) async {
    final stopwatch = Stopwatch()..start();
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await request().timeout(maxTimeout); // 设置单次请求的超时时间
      } catch (e, stackTrace) {
        LogUtil.logError('请求失败，重试第 $attempt 次...', e, stackTrace);
        if (onRetry != null) {
          onRetry(attempt + 1, retries - attempt - 1); // 传递当前尝试次数和剩余次数
        }
        // 检查是否超过最大重试次数或总超时时间
        if (attempt >= retries - 1 || stopwatch.elapsed > maxTimeout) {
          return null; // 超过限制，返回 null
        }
        await Future.delayed(retryDelay); // 等待一段时间后重试
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

  /// 获取远程播放列表数据
  static Future<String> _fetchData() async {
    try {
      final defaultM3u = EnvUtil.videoDefaultChannelHost();
      // 添加时间参数以避免缓存
      final String timeParam = DateFormat('yyyyMMddHH').format(DateTime.now());
      final urlWithTimeParam = '$defaultM3u?time=$timeParam';
      final res = await HttpUtil().getRequest(urlWithTimeParam);
      return res ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      throw Exception('Network error: $e'); // 抛出异常以便上层捕获并处理
    }
  }

  /// 获取并处理多个M3U列表的合并
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      // 按分隔符拆分多个URL
      List<String> urls = url.split('||');
      final results = await Future.wait(urls.map(_fetchM3uData));
      final playlists = <PlaylistModel>[];

      // 解析每个成功获取的M3U数据
      for (var m3uData in results) {
        if (m3uData != null) {
          final parsedPlaylist = await _parseM3u(m3uData);
          playlists.add(parsedPlaylist);
        }
      }

      // 如果没有成功解析任何播放列表，返回null
      if (playlists.isEmpty) return null;

      // 合并所有解析成功的播放列表
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
          Duration(seconds: 8), // 单个请求的超时时间
        ));
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      return null;
    }
  }

  /// 合并多个 PlaylistModel，避免重复的播放地址
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    try {
      PlaylistModel mergedPlaylist = PlaylistModel();
      mergedPlaylist.playList = {};

      // 使用ID映射表记录已合并的频道，避免重复处理
      Map<String, PlayModel> mergedChannelsById = {};

      // 遍历所有播放列表进行合并
      for (PlaylistModel playlist in playlists) {
        playlist.playList?.forEach((category, groups) {
          mergedPlaylist.playList![category] ??= {};
          groups.forEach((groupTitle, channels) {
            mergedPlaylist.playList![category]![groupTitle] ??= {};
            channels.forEach((channelName, channelModel) {
              // 使用频道ID作为唯一标识
              if (channelModel.id != null && channelModel.id!.isNotEmpty) {
                String tvgId = channelModel.id!;

                // 跳过没有播放地址的频道
                if (channelModel.urls == null || channelModel.urls!.isEmpty) {
                  return;
                }

                // 如果已存在相同ID的频道，合并播放地址
                if (mergedChannelsById.containsKey(tvgId)) {
                  PlayModel existingChannel = mergedChannelsById[tvgId]!;
                  // 使用Set去重合并播放地址
                  Set<String> existingUrls = existingChannel.urls?.toSet() ?? {};
                  Set<String> newUrls = channelModel.urls?.toSet() ?? {};
                  existingUrls.addAll(newUrls);
                  existingChannel.urls = existingUrls.toList();
                  mergedChannelsById[tvgId] = existingChannel;
                } else {
                  // 新频道直接添加到映射表
                  mergedChannelsById[tvgId] = channelModel;
                }

                // 更新合并后的播放列表
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

  /// 解析 M3U 文件并转换为 PlaylistModel 格式
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      // 按行分割M3U文件内容
      final lines = m3u.split(RegExp(r'\r?\n'));
      final playListModel = PlaylistModel()..playList = {};
      String currentCategory = Config.allChannelsKey; // 默认分类
      String tempGroupTitle = '';
      String tempChannelName = '';
      bool hasCategory = false;

      // 逐行解析M3U文件
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;

        if (line.startsWith('#EXTM3U')) {
          // 解析M3U文件头，提取EPG URL等信息
          _parseExtM3u(line, playListModel);
        } else if (line.startsWith('#CATEGORY:')) {
          // 解析分类标签，更新当前分类
          currentCategory = _parseCategory(line);
          hasCategory = true;
        } else if (line.startsWith('#EXTINF:')) {
          // 解析频道信息标签
          var result = _parseExtInf(line, lines, i, playListModel, currentCategory);
          i = result['nextIndex'] as int; // 更新索引，跳过已处理的行
          tempGroupTitle = result['groupTitle'] as String;
          tempChannelName = result['channelName'] as String;
        } else if (isLiveLink(line)) {
          // 处理直播链接行
          _addLiveLink(line, playListModel, currentCategory, tempGroupTitle, tempChannelName);
        }
      }
      return playListModel;
    } catch (e, stackTrace) {
      LogUtil.logError('解析M3U文件失败', e, stackTrace);
      return PlaylistModel();
    }
  }

  /// 解析 #EXTM3U 行，提取 EPG URL 等元数据
  static void _parseExtM3u(String line, PlaylistModel model) {
    // 去除引号并按空格分割参数
    final params = line.replaceAll('"', '').split(' ');
    // 查找并提取EPG URL参数
    final tvgUrl = params.firstWhere((e) => e.startsWith('x-tvg-url'), orElse: () => '').split('=').last;
    if (tvgUrl.isNotEmpty) model.epgUrl = tvgUrl;
  }

  /// 解析 #CATEGORY 行，返回分类名称
  static String _parseCategory(String line) {
    final category = line.replaceFirst('#CATEGORY:', '').trim();
    return category.isEmpty ? Config.allChannelsKey : category;
  }

  /// 解析 #EXTINF 行，提取频道信息并构建播放模型
  static Map<String, dynamic> _parseExtInf(String line, List<String> lines, int index,
      PlaylistModel model, String currentCategory) {
    // 处理不同格式的EXTINF行
    if (line.startsWith('#EXTINF:-1,')) {
      line = line.replaceFirst('#EXTINF:-1,', '#EXTINF:-1 ');
    }
    final lineList = line.split(',');
    List<String> params = lineList.first.replaceAll('"', '').split(' ');

    // 提取分组信息，默认为"默认"
    final groupStr = params.firstWhere(
        (element) => element.startsWith('group-title='),
        orElse: () => 'group-title=${S.current.defaultText}');
    final tempGroupTitle = groupStr.split('=').last;

    // 提取频道元数据：图标、ID和名称
    String tvgLogo = params.firstWhere((element) => element.startsWith('tvg-logo='), orElse: () => '').split('=').last;
    String tvgId = params.firstWhere((element) => element.startsWith('tvg-id='), orElse: () => '').split('=').last;
    String tvgName = params.firstWhere((element) => element.startsWith('tvg-name='), orElse: () => '').split('=').last;

    // 如果没有ID但有名称，使用名称作为ID
    if (tvgId.isEmpty && tvgName.isNotEmpty) {
      tvgId = tvgName;
    }
    // 如果没有ID，跳过此频道
    if (tvgId.isEmpty) {
      return {'nextIndex': index, 'groupTitle': tempGroupTitle, 'channelName': ''};
    }

    // 获取频道名称
    final tempChannelName = lineList.last;

    // 获取或创建分类、分组和频道的嵌套结构
    model.playList![currentCategory] ??= {};
    model.playList![currentCategory]![tempGroupTitle] ??= {};
    PlayModel channel = model.playList![currentCategory]![tempGroupTitle]![tempChannelName] ??
        PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

    // 处理后续行中的直播链接
    int nextIndex = index;
    if (index + 1 < lines.length && isLiveLink(lines[index + 1])) {
      // 直接下一行是链接
      channel.urls ??= [];
      if (lines[index + 1].isNotEmpty) channel.urls!.add(lines[index + 1]);
      model.playList![currentCategory]![tempGroupTitle]![tempChannelName] = channel;
      nextIndex = index + 1;
    } else if (index + 2 < lines.length && isLiveLink(lines[index + 2])) {
      // 下下行是链接（有些M3U格式会在中间插入空行）
      channel.urls ??= [];
      if (lines[index + 2].isNotEmpty) channel.urls!.add(lines[index + 2]);
      model.playList![currentCategory]![tempGroupTitle]![tempChannelName] = channel;
      nextIndex = index + 2;
    }

    return {'nextIndex': nextIndex, 'groupTitle': tempGroupTitle, 'channelName': tempChannelName};
  }

  /// 添加直播链接到播放模型
  static void _addLiveLink(String line, PlaylistModel model, String currentCategory,
      String tempGroupTitle, String tempChannelName) {
    if (line.isNotEmpty) {
      // 确保URLs列表已初始化
      model.playList![currentCategory] ??= {};
      model.playList![currentCategory]![tempGroupTitle] ??= {};
      model.playList![currentCategory]![tempGroupTitle]![tempChannelName] ??=
          PlayModel(id: '', group: tempGroupTitle, title: tempChannelName, urls: []);
      model.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls ??= [];
      // 添加链接到URLs列表
      model.playList![currentCategory]![tempGroupTitle]![tempChannelName]!.urls!.add(line);
    }
  }

  /// 判断链接是否为有效的直播链接
  static bool isLiveLink(String link) {
    const protocols = ['http', 'https', 'rtmp', 'rtsp', 'mms', 'ftp'];
    return protocols.any((protocol) => link.toLowerCase().startsWith(protocol));
  }
}
