import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:async/async.dart' show LineSplitter;
import 'package:sp_util/sp_util.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart' show Options;
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/entity/subScribe_model.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 封装M3U解析结果
class M3uResult {
  final PlaylistModel? data; // 解析后的播放列表数据
  final String? errorMessage; // 错误信息
  final ErrorType? errorType; // 错误类型

  M3uResult({this.data, this.errorMessage, this.errorType});
}

/// 定义M3U处理错误类型
enum ErrorType {
  networkError, // 网络错误
  parseError,   // 解析错误
  timeout,      // 超时错误
}

class M3uUtil {
  M3uUtil._();

  /// 预编译正则表达式以提升解析效率
  static final RegExp extInfRegex = RegExp(r'#EXTINF:-1\s*(?:([^,]*?),)?(.+)', multiLine: true);
  static final RegExp paramRegex = RegExp("(\\w+[-\\w]*)=[\"']?([^\"'\\s]+)[\"']?");
  
  /// 预编译有效URL前缀集合以优化匹配
  static final Set<String> _validUrlPrefixes = {
    'http://', 'https://', 'rtmp://', 'rtsp://', 'mms://', 'ftp://'
  };

  /// 缓存标记常量
  static const String _CACHE_MARKER = '__USE_CACHE__';

  /// 从M3U数据中提取版本号
  static String? _extractVersion(String m3uData) {
    try {
      // 优先查找 #VERSION: 标记
      final versionMatch = RegExp(r'^#VERSION:(\S+)', multiLine: true).firstMatch(m3uData);
      if (versionMatch != null) {
        final version = versionMatch.group(1);
        LogUtil.i('找到版本号 (VERSION标记): $version');
        return version;
      }
      
      // 其次查找 #EXTM3U 中的 version 参数
      final extMatch = RegExp(r'#EXTM3U.*version=["\']?([^"\'\s]+)["\']?').firstMatch(m3uData);
      if (extMatch != null) {
        final version = extMatch.group(1);
        LogUtil.i('找到版本号 (EXTM3U参数): $version');
        return version;
      }
      
      LogUtil.i('未找到版本号');
      return null;
    } catch (e) {
      LogUtil.e('提取版本号失败: $e');
      return null;
    }
  }

  /// 创建缓存标记
  static PlaylistModel _createCacheMarker() {
    return PlaylistModel()..playList = {_CACHE_MARKER: {}};
  }

  /// 判断是否为缓存标记
  static bool isCacheMarker(PlaylistModel? model) {
    return model?.playList?.containsKey(_CACHE_MARKER) ?? false;
  }

  /// 检查播放列表文件是否存在
  static Future<bool> _playlistFileExists() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/playListModel.json');
      return await file.exists();
    } catch (e) {
      LogUtil.e('检查播放列表文件失败: $e');
      return false;
    }
  }

  /// 加载并解析本地M3U文件为PlaylistModel
  static Future<PlaylistModel> _loadLocalM3uData() async {
    try {
      final encryptedM3uData = await rootBundle.loadString('assets/playlists.m3u');
      String decryptedM3uData;
      
      if (encryptedM3uData.startsWith('#EXTM3U') || encryptedM3uData.startsWith('#EXTINF')) {
        decryptedM3uData = encryptedM3uData;
      } else {
        decryptedM3uData = _decodeEntireFile(encryptedM3uData);
      }
      
      return await _parseM3u(decryptedM3uData);
    } catch (e, stackTrace) {
      LogUtil.logError('加载本地播放列表失败', e, stackTrace);
      return PlaylistModel();
    }
  }

  /// 并行获取并合并远程与本地M3U数据
  static Future<M3uResult> getDefaultM3uData() async {
    try {
      // 读取缓存信息
      final cachedVersion = SpUtil.getString('M3uVersion');
      final hasLocalFile = await _playlistFileExists();
      
      LogUtil.i('缓存版本: $cachedVersion, 本地文件存在: $hasLocalFile');

      // 并行执行远程和本地数据获取
      final remoteFuture = _fetchData();
      final localFuture = _loadLocalM3uData();

      final String? remoteM3uData = await remoteFuture;
      final PlaylistModel localPlaylistData = await localFuture;

      _logPlaylistStats('本地播放列表', localPlaylistData);

      PlaylistModel parsedData;
      bool remoteDataSuccess = false;

      if (remoteM3uData == null || remoteM3uData.isEmpty) {
        LogUtil.logError('远程播放列表获取失败，使用本地 playlists.m3u', 'remoteM3uData为空');
        
        // 远程获取失败，保存error标记
        await SpUtil.putString('M3uVersion', 'error');
        
        // 如果本地文件存在且上次也是失败，使用缓存
        if (hasLocalFile && cachedVersion == 'error') {
          LogUtil.i('远程获取失败，使用缓存播放列表');
          return M3uResult(data: _createCacheMarker());
        }
        
        parsedData = localPlaylistData;
        if (parsedData.playList.isEmpty) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      } else {
        // 远程获取成功，提取版本号
        final version = _extractVersion(remoteM3uData);
        
        // 检查是否可以使用缓存
        if (version != null && version.isNotEmpty) {
          if (hasLocalFile && version == cachedVersion) {
            LogUtil.i('版本号未变 ($version)，使用缓存播放列表');
            return M3uResult(data: _createCacheMarker());
          }
          // 保存新版本号
          await SpUtil.putString('M3uVersion', version);
          LogUtil.i('保存新版本号: $version');
        } else {
          // 没有版本号，保存error
          await SpUtil.putString('M3uVersion', 'error');
          LogUtil.i('未找到版本号，保存为error');
        }
        
        remoteDataSuccess = true;
        PlaylistModel remotePlaylistData;
        
        if (remoteM3uData.contains('||')) {
          remotePlaylistData = await fetchAndMergeM3uData(remoteM3uData) ?? PlaylistModel();
        } else {
          remotePlaylistData = await _parseM3u(remoteM3uData);
        }
        
        _logPlaylistStats('远程播放列表', remotePlaylistData);
        
        if (remotePlaylistData.playList.isEmpty) {
          LogUtil.logError('远程播放列表解析失败，使用本地数据', '远程数据解析为空');
          parsedData = localPlaylistData;
          remoteDataSuccess = false;
          if (parsedData.playList.isEmpty) {
            return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
          }
        } else {
          if (localPlaylistData.playList.isNotEmpty) {
            LogUtil.i('合并本地和远程播放列表');
            // 优化：将远程数据合并到本地数据中，减少内存占用
            _mergeIntoFirst(localPlaylistData, remotePlaylistData);
            parsedData = localPlaylistData;
            _logPlaylistStats('合并完成', parsedData);
          } else {
            LogUtil.i('本地数据为空，仅使用远程数据');
            parsedData = remotePlaylistData;
          }
        }
      }

      final favoritePlaylist = await getOrCreateFavoriteList();
      await updateFavoriteChannelsWithRemoteData(parsedData, PlaylistModel(playList: favoritePlaylist));
      
      try {
        parsedData.playList = _insertFavoritePlaylistFirst(
          parsedData.playList.cast<String, Map<String, Map<String, PlayModel>>>(), 
          PlaylistModel(playList: favoritePlaylist)
        );
      } catch (e, stackTrace) {
        LogUtil.logError('插入收藏列表时类型转换失败', e, stackTrace);
        final emptyPlaylist = <String, Map<String, Map<String, PlayModel>>>{};
        parsedData.playList = _insertFavoritePlaylistFirst(emptyPlaylist, PlaylistModel(playList: favoritePlaylist));
      }

      if (remoteDataSuccess) {
        await saveLocalData([SubScribeModel(
          time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full), 
          link: 'default', 
          selected: true
        )]);
      }
      
      return M3uResult(data: parsedData);
    } catch (e, stackTrace) {
      LogUtil.logError('获取播放列表出错', e, stackTrace);
      return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.networkError);
    }
  }

  /// 解密M3U文件内容（Base64解码后XOR解密）
  static String _decodeEntireFile(String encryptedContent) {
    try {
      final Uint8List decodedBytes = base64Decode(encryptedContent);
      final Uint8List keyBytes = utf8.encode(Config.m3uXorKey);
      final int keyLength = keyBytes.length;
      
      for (int i = 0; i < decodedBytes.length; i++) {
        decodedBytes[i] = decodedBytes[i] ^ keyBytes[i % keyLength];
      }
      
      return utf8.decode(decodedBytes);
    } catch (e, stackTrace) {
      LogUtil.logError('解密M3U文件失败', e, stackTrace);
      return encryptedContent;
    }
  }

  /// 获取或创建本地收藏播放列表
  static Future<Map<String, Map<String, Map<String, PlayModel>>>> getOrCreateFavoriteList() async {
    final favoriteData = await _getCachedFavoriteM3uData();
    if (favoriteData.isEmpty) {
      Map<String, Map<String, Map<String, PlayModel>>> favoritePlaylist = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
      LogUtil.i('创建收藏列表: $favoritePlaylist');
      return favoritePlaylist;
    } else {
      PlaylistModel favoritePlaylistModel = PlaylistModel.fromString(favoriteData);
      Map<String, Map<String, Map<String, PlayModel>>> favoritePlaylist = favoritePlaylistModel.playList.cast<String, Map<String, Map<String, PlayModel>>>() ?? {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
      LogUtil.i('解析缓存收藏列表: $favoritePlaylist');
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
    remotePlaylist.playList.forEach((category, groups) {
      if (groups is Map) {
        groups.forEach((groupTitle, channels) {
          if (channels is Map) {
            channels.forEach((channelName, channelModel) {
              if (channelModel is PlayModel && channelModel.id != null && channelModel.urls != null) {
                remoteIdToUrls[channelModel.id!] = channelModel.urls!;
              }
            });
          }
        });
      }
    });
    
    favoriteCategory.forEach((groupTitle, channels) {
      channels.forEach((channelName, favoriteChannel) {
        if (favoriteChannel.id != null && remoteIdToUrls.containsKey(favoriteChannel.id!)) {
          final urls = remoteIdToUrls[favoriteChannel.id!]!;
          final validUrls = urls.where((url) => isLiveLink(url)).toList();
          if (validUrls.isNotEmpty) favoriteChannel.urls = validUrls;
        }
      });
    });
  }

  /// 获取本地缓存订阅数据
  static Future<List<SubScribeModel>> getLocalData() async {
    try {
      return SpUtil.getObjList('local_m3u', (v) => SubScribeModel.fromJson(v), defValue: <SubScribeModel>[])!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取订阅数据失败', e, stackTrace);
      return [];
    }
  }

  /// 获取远程M3U播放列表数据
  static Future<String?> _fetchUrlData(String url, {Duration timeout = const Duration(seconds: 8), int retryCount = 1, Duration retryDelay = const Duration(seconds: 1)}) async {
    try {
      final String timeParam = DateFormat('yyyyMMddHH').format(DateTime.now());
      final urlWithTimeParam = '$url?time=$timeParam';
      // 使用 HttpUtil 的重试机制，传递重试参数
      final res = await HttpUtil().getRequest(
        urlWithTimeParam,
        retryCount: retryCount,
        retryDelay: retryDelay,
        options: Options(
          extra: {
            'connectTimeout': timeout,
            'receiveTimeout': timeout,
          },
        ),
      );
      return res ?? '';
    } catch (e, stackTrace) {
      LogUtil.logError('获取远程播放列表失败', e, stackTrace);
      throw Exception('Network error: $e');
    }
  }

  /// 获取默认远程M3U播放列表
  static Future<String?> _fetchData({String? url, Duration timeout = const Duration(seconds: 8)}) async {
    // 传递重试参数，让 HttpUtil 处理重试
    return _fetchUrlData(url ?? EnvUtil.videoDefaultChannelHost(), timeout: timeout, retryCount: 1);
  }

  /// 获取并合并多个M3U播放列表
  static Future<PlaylistModel?> fetchAndMergeM3uData(String url) async {
    try {
      List<String> urls = url.split('||');
      // 并行获取所有URL的数据，使用统一的重试策略
      final results = await Future.wait(
        urls.map((u) => _fetchUrlData(u, timeout: const Duration(seconds: 8), retryCount: 1))
      );
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

  /// 将第二个播放列表合并到第一个播放列表中（原地修改，减少内存占用）
  static void _mergeIntoFirst(PlaylistModel first, PlaylistModel second) {
    try {
      // 用于存储已处理的频道ID和URL
      final Map<String, Set<String>> processedUrls = {};
      
      // 第一步：收集第一个播放列表中所有频道的ID和URL
      _traversePlaylist(first, (category, groupTitle, channelName, channelModel) {
        if (channelModel.id != null && channelModel.id!.isNotEmpty) {
          processedUrls[channelModel.id!] = Set<String>.from(channelModel.urls ?? []);
        }
      });
      
      LogUtil.i('第一个播放列表包含 ${processedUrls.length} 个频道');
      
      // 第二步：遍历第二个播放列表，合并数据
      _traversePlaylist(second, (category, groupTitle, channelName, channelModel) {
        if (channelModel.id != null && channelModel.id!.isNotEmpty && 
            channelModel.urls != null && channelModel.urls!.isNotEmpty) {
          
          final String tvgId = channelModel.id!;
          
          // 检查是否已存在该频道
          if (processedUrls.containsKey(tvgId)) {
            // 合并URL
            processedUrls[tvgId]!.addAll(channelModel.urls!);
            
            // 更新第一个播放列表中对应频道的URL
            _updateChannelUrls(first, tvgId, processedUrls[tvgId]!.toList());
          } else {
            // 新频道，添加到第一个播放列表
            final groupMap = _ensureTypedGroupMap(first.playList, category, groupTitle);
            groupMap[channelName] = PlayModel(
              id: channelModel.id,
              title: channelModel.title,
              group: groupTitle,
              logo: channelModel.logo,
              urls: List.from(channelModel.urls ?? []),
            );
            
            // 记录新频道
            processedUrls[tvgId] = Set<String>.from(channelModel.urls ?? []);
          }
        }
      });
      
      LogUtil.i('合并后共 ${processedUrls.length} 个频道');
      
      // 清理内存
      processedUrls.clear();
      
    } catch (e, stackTrace) {
      LogUtil.logError('合并播放列表失败', e, stackTrace);
    }
  }

  /// 更新播放列表中指定ID频道的URL
  static void _updateChannelUrls(PlaylistModel playlist, String tvgId, List<String> urls) {
    _traversePlaylist(playlist, (category, groupTitle, channelName, channelModel) {
      if (channelModel.id == tvgId) {
        channelModel.urls = urls;
      }
    });
  }

/// 合并多个播放列表并去重（优化版 - 保持原始逻辑）
static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
  try {
    // 优化1：提前返回特殊情况
    if (playlists.isEmpty) {
      return PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
    }
    if (playlists.length == 1) {
      return playlists[0];
    }
    
    // 用于存储合并后的频道数据（按id索引）
    final Map<String, PlayModel> mergedChannelsById = {};
    final Map<String, Set<String>> urlCacheById = {};
    
    // 第一次遍历：收集所有频道数据并合并URLs（保持原始逻辑）
    for (int i = 0; i < playlists.length; i++) {
      final playlist = playlists[i];
      LogUtil.i('处理第 ${i + 1} 个播放列表');
      
      playlist.playList.forEach((category, groups) {
        if (groups is! Map<String, dynamic>) return;
        
        groups.forEach((groupTitle, channels) {
          if (channels is! Map<String, dynamic>) return;
          
          channels.forEach((channelName, channelModel) {
            if (channelModel is! PlayModel) return;
            
            final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
            final bool hasValidUrls = channelModel.urls != null && channelModel.urls!.isNotEmpty;
            
            if (hasValidId && hasValidUrls) {
              final String tvgId = channelModel.id!;
              
              if (mergedChannelsById.containsKey(tvgId)) {
                Set<String> urlSet = urlCacheById[tvgId]!;
                urlSet.addAll(channelModel.urls!);
                mergedChannelsById[tvgId]!.urls = urlSet.toList();
              } else {
                mergedChannelsById[tvgId] = PlayModel(
                  id: channelModel.id,
                  title: channelModel.title,
                  group: channelModel.group,
                  logo: channelModel.logo,
                  urls: List.from(channelModel.urls ?? []),
                );
                urlCacheById[tvgId] = Set<String>.from(channelModel.urls ?? []);
              }
            }
          });
        });
      });
    }
    
    LogUtil.i('收集 ${mergedChannelsById.length} 个唯一频道');
    
    // 优化：直接在第一个播放列表上构建，减少内存分配
    final mergedPlaylist = playlists[0];
    
    // 清空第一个播放列表的内容，准备重建
    mergedPlaylist.playList.clear();
    
    // 第二次遍历：构建最终的播放列表结构（保持原始逻辑）
    for (final playlist in playlists) {
      playlist.playList.forEach((category, groups) {
        if (groups is! Map<String, dynamic>) return;
        
        groups.forEach((groupTitle, channels) {
          if (channels is! Map<String, dynamic>) return;
          
          final categoryMap = mergedPlaylist.playList.putIfAbsent(
            category,
            () => <String, Map<String, PlayModel>>{}
          ) as Map<String, Map<String, PlayModel>>;
          
          final groupMap = categoryMap.putIfAbsent(
            groupTitle,
            () => <String, PlayModel>{}
          );
          
          channels.forEach((channelName, channelModel) {
            if (channelModel is! PlayModel) return;
            
            final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
            
            if (hasValidId && mergedChannelsById.containsKey(channelModel.id!)) {
              final mergedChannel = mergedChannelsById[channelModel.id!]!;
              groupMap[channelName] = PlayModel(
                id: mergedChannel.id,
                title: channelModel.title ?? mergedChannel.title,
                group: groupTitle,
                logo: channelModel.logo ?? mergedChannel.logo,
                urls: List.from(mergedChannel.urls ?? []),
              );
            } else if (channelModel.urls != null && channelModel.urls!.isNotEmpty) {
              groupMap[channelName] = channelModel;
              LogUtil.i('添加无ID频道到 $category/$groupTitle/$channelName');
            }
          });
        });
      });
    }
    
    // 清理临时数据结构
    mergedChannelsById.clear();
    urlCacheById.clear();
    
    _logPlaylistStats('合并完成', mergedPlaylist);
    
    return mergedPlaylist;
  } catch (e, stackTrace) {
    LogUtil.logError('合并播放列表失败', e, stackTrace);
    return PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
  }
}

  /// 安全遍历播放列表的辅助方法
  static void _traversePlaylist(PlaylistModel playlist, 
      void Function(String category, String groupTitle, String channelName, PlayModel channelModel) callback) {
    playlist.playList.forEach((category, groups) {
      if (groups is Map<String, dynamic>) {
        groups.forEach((groupTitle, channels) {
          if (channels is Map<String, dynamic>) {
            channels.forEach((channelName, channelModel) {
              if (channelModel is PlayModel) {
                callback(category, groupTitle, channelName, channelModel);
              }
            });
          }
        });
      }
    });
  }

  /// 确保指定分类和分组的Map存在（类型安全版本）
  static Map<String, PlayModel> _ensureTypedGroupMap(
    Map<String, dynamic> playList,
    String category,
    String groupTitle,
  ) {
    // 确保分类存在
    if (!playList.containsKey(category)) {
      playList[category] = <String, Map<String, PlayModel>>{};
    }
    final categoryMap = playList[category] as Map<String, Map<String, PlayModel>>;
    
    // 确保分组存在
    if (!categoryMap.containsKey(groupTitle)) {
      categoryMap[groupTitle] = <String, PlayModel>{};
    }
    return categoryMap[groupTitle]!;
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

  /// 解析M3U文件为PlaylistModel
  static Future<PlaylistModel> _parseM3u(String m3u) async {
    try {
      final lines = LineSplitter.split(m3u).toList();
      final playListModel = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
      String currentCategory = Config.allChannelsKey;
      String tempGroupTitle = '';
      String tempChannelName = '';

      final List<String> filterKeywords = (Config.cnversion && Config.cnplayListrule.isNotEmpty)
        ? Config.cnplayListrule.split('@')
        : [];
      
      if (filterKeywords.isNotEmpty) {
        LogUtil.i('启用关键字过滤: $filterKeywords');
      }
      
      final List<String> lowerFilterKeywords = filterKeywords
          .where((k) => k.isNotEmpty)
          .map((k) => k.toLowerCase())
          .toList();
      
      final Map<String, bool> filterCache = {};
      
      bool shouldFilter(String text) {
        if (text.isEmpty || lowerFilterKeywords.isEmpty) return false;
        
        if (filterCache.containsKey(text)) {
          return filterCache[text]!;
        }
        
        final lowerText = text.toLowerCase();
        final result = lowerFilterKeywords.any((keyword) => lowerText.contains(keyword));
        filterCache[text] = result;
        return result;
      }
      
      bool hasCategory = lines.any((line) => line.trim().startsWith('#CATEGORY:'));
      LogUtil.i('M3U数据 ${hasCategory ? "包含" : "不包含"} #CATEGORY标签');
      PlayModel? currentChannel;
      
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
            String newCategory = line.substring(10).trim();
            currentCategory = newCategory.isNotEmpty ? newCategory : Config.allChannelsKey;
            
            if (shouldFilter(currentCategory)) {
              LogUtil.i('过滤分类: $currentCategory');
              while (i + 1 < lines.length && !lines[i + 1].trim().startsWith('#CATEGORY:')) {
                i++;
              }
              continue;
            }
          } else if (line.startsWith('#EXTINF:')) {
            if (shouldFilter(currentCategory)) {
              continue;
            }

            // 保持原始的正则解析，确保兼容性
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

            // 优化：只在有参数时才使用正则
            if (paramsStr.isNotEmpty) {
              final params = paramRegex.allMatches(paramsStr);
              for (var param in params) {
                final key = param.group(1)!;
                final value = param.group(2)!;
                switch (key) {
                  case 'group-title':
                    groupTitle = value;
                    break;
                  case 'tvg-logo':
                    tvgLogo = value;
                    break;
                  case 'tvg-id':
                    tvgId = value;
                    break;
                  case 'tvg-name':
                    tvgName = value;
                    break;
                }
              }
            }

            if (tvgId.isEmpty && tvgName.isNotEmpty) tvgId = tvgName;
            if (tvgId.isEmpty) {
              LogUtil.logError('缺少 tvg-id 或 tvg-name', '行内容: $line');
              continue;
            }

            tempGroupTitle = groupTitle;
            tempChannelName = channelName;
            
            if (shouldFilter(tempGroupTitle)) {
              LogUtil.i('过滤分组: $tempGroupTitle');
              continue;
            }
            
            final groupMap = _ensureGroupMap(playListModel.playList, currentCategory, tempGroupTitle);
            currentChannel = groupMap[tempChannelName] ??
                PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

            bool foundUrl = false;
            for (int j = i + 1; j < lines.length && !foundUrl; j++) {
              final nextLine = lines[j].trim();
              if (nextLine.isEmpty) continue;
              if (nextLine.startsWith('#')) break;
              
              if (isLiveLink(nextLine)) {
                if (currentChannel != null) {
                  currentChannel.urls ??= [];
                  currentChannel.urls!.add(nextLine);
                  groupMap[tempChannelName] = currentChannel;
                  i = j;
                  foundUrl = true;
                }
              } else {
                break;
              }
            }
          } else if (isLiveLink(line)) {
            if (shouldFilter(currentCategory)) {
              continue;
            }
            
            if (shouldFilter(tempGroupTitle)) {
              continue;
            }
            
            final groupMap = _ensureGroupMap(playListModel.playList, currentCategory, tempGroupTitle);
            
            if (!groupMap.containsKey(tempChannelName)) {
              groupMap[tempChannelName] = PlayModel(id: '', group: tempGroupTitle, title: tempChannelName, urls: []);
            }
            
            final channel = groupMap[tempChannelName]!;
            channel.urls ??= [];
            channel.urls!.add(line);
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
            
            if (shouldFilter(tempGroup)) {
              continue;
            }
            
            if (isLiveLink(channelLink)) {
              if (shouldFilter(groupTitle)) {
                LogUtil.i('过滤分组: $groupTitle');
                continue;
              }
              
              final channelMap = _ensureGroupMap(playListModel.playList, tempGroup, groupTitle);
              
              final channel = channelMap[groupTitle] ??
                  PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
              channel.urls ??= [];
              if (channelLink.isNotEmpty) channel.urls!.add(channelLink);
              channelMap[groupTitle] = channel;
            } else {
              tempGroup = groupTitle.isEmpty ? '${S.current.defaultText}${i + 1}' : groupTitle;
              
              if (shouldFilter(tempGroup)) {
                LogUtil.i('过滤分类: $tempGroup');
                continue;
              }
              
              playListModel.playList[tempGroup] ??= <String, Map<String, PlayModel>>{};
            }
          }
        }
      }
      
      if (filterKeywords.isNotEmpty) {
        LogUtil.i('已应用关键字过滤，缓存命中: ${filterCache.length} 个');
      }
      
      return playListModel;
    } catch (e, stackTrace) {
      LogUtil.logError('解析M3U文件失败', e, stackTrace);
      return PlaylistModel(playList: {Config.allChannelsKey: <String, Map<String, PlayModel>>{}});
    }
  }

  /// 判断链接是否为有效直播链接
  static bool isLiveLink(String link) {
    if (link.isEmpty || link.startsWith('#')) return false;
    
    for (final prefix in _validUrlPrefixes) {
      if (link.startsWith(prefix)) return true;
    }
    return false;
  }

  /// 确保指定分类和分组的Map存在
  static Map<String, PlayModel> _ensureGroupMap(
    Map<String, dynamic> playList,
    String category,
    String groupTitle,
  ) {
    if (!playList.containsKey(category)) {
      playList[category] = <String, Map<String, PlayModel>>{};
    }
    final categoryMap = playList[category] as Map<String, Map<String, PlayModel>>;
    
    if (!categoryMap.containsKey(groupTitle)) {
      categoryMap[groupTitle] = <String, PlayModel>{};
    }
    return categoryMap[groupTitle]!;
  }

  /// 输出播放列表统计信息
  static void _logPlaylistStats(String title, PlaylistModel playlist) {
    int totalCategories = playlist.playList.length;
    int totalChannels = 0;
    
    playlist.playList.forEach((category, groups) {
      if (groups is Map) {
        int categoryChannels = 0;
        groups.forEach((groupTitle, channels) {
          if (channels is Map) {
            categoryChannels += channels.length;
          }
        });
        totalChannels += categoryChannels;
        LogUtil.i('分类 "$category" 包含 $categoryChannels 个频道');
      }
    });
    
    if (title == '合并完成') {
      LogUtil.i('$title: 共 $totalCategories 个分类，$totalChannels 个频道');
    }
  }
}
