import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:async/async.dart' show LineSplitter;
import 'package:sp_util/sp_util.dart';
import 'package:intl/intl.dart';
import 'package:itvapp_live_tv/entity/subScribe_model.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/zhConverter.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

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

  // 缓存常用的正则表达式 - 优化点：预编译正则表达式
  static final RegExp extInfRegex = RegExp(r'#EXTINF:-1\s*(?:([^,]*?),)?(.+)', multiLine: true);
  static final RegExp paramRegex = RegExp("(\\w+[-\\w]*)=[\"']?([^\"'\\s]+)[\"']?");
  
  // 优化点：预编译URL前缀检查的Set，比多个startsWith更快
  static final Set<String> _validUrlPrefixes = {
    'http://', 'https://', 'rtmp://', 'rtsp://', 'mms://', 'ftp://'
  };

/// 加载本地 M3U 数据文件并解析
static Future<PlaylistModel> _loadLocalM3uData() async {
  try {
    final encryptedM3uData = await rootBundle.loadString('assets/playlists.m3u');
    String decryptedM3uData;
    
    // 判断本地数据是否已经加密，如果加密就先解密
    if (encryptedM3uData.startsWith('#EXTM3U') || encryptedM3uData.startsWith('#EXTINF')) {
      decryptedM3uData = encryptedM3uData;
    } else {
      decryptedM3uData = _decodeEntireFile(encryptedM3uData);
    }
    
    return await _parseM3u(decryptedM3uData);
  } catch (e, stackTrace) {
    LogUtil.logError('加载本地播放列表失败', e, stackTrace);
    return PlaylistModel(); // 返回空的播放列表，确保不影响远程数据处理
  }
}

/// 获取远程播放列表，并行加载本地数据进行合并
static Future<M3uResult> getDefaultM3uData({Function(int attempt, int remaining)? onRetry}) async {
  try {
    // 并行启动远程和本地数据获取，减少总等待时间
    final remoteFuture = _retryRequest<String>(
      _fetchData,
      onRetry: onRetry,
      maxTimeout: const Duration(seconds: 30),
    );
    final localFuture = _loadLocalM3uData();

    // 等待两个任务完成
    final String? remoteM3uData = await remoteFuture;
    final PlaylistModel localPlaylistData = await localFuture;

    // 输出本地数据解析结果
    localPlaylistData.playList.forEach((category, groups) {
      if (groups is Map) {
        int channelCount = 0;
        groups.forEach((groupTitle, channels) {
          if (channels is Map) {
            channelCount += channels.length;
          }
        });
        LogUtil.i('分类 "$category": $channelCount 个频道');
      }
    });

    PlaylistModel parsedData;
    bool remoteDataSuccess = false;

    if (remoteM3uData == null || remoteM3uData.isEmpty) {
      // 远程数据获取失败，使用本地数据
      LogUtil.logError('远程播放列表获取失败，使用本地 playlists.m3u', 'remoteM3uData为空');
      parsedData = localPlaylistData;
      if (parsedData.playList.isEmpty) {
        return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
      }
    } else {
      // 远程数据获取成功，处理远程数据
      remoteDataSuccess = true;
      PlaylistModel remotePlaylistData;
      
      if (remoteM3uData.contains('||')) {
        // 处理多源远程数据合并
        remotePlaylistData = await fetchAndMergeM3uData(remoteM3uData) ?? PlaylistModel();
      } else {
        // 处理单源远程数据
        remotePlaylistData = await _parseM3u(remoteM3uData);
      }
      
      // 输出远程数据解析结果
      remotePlaylistData.playList.forEach((category, groups) {
        if (groups is Map) {
          int channelCount = 0;
          groups.forEach((groupTitle, channels) {
            if (channels is Map) {
              channelCount += channels.length;
            }
          });
          LogUtil.i('分类 "$category": $channelCount 个频道');
        }
      });
      
      if (remotePlaylistData.playList.isEmpty) {
        // 远程数据解析失败，回退到本地数据
        LogUtil.logError('远程播放列表解析失败，使用本地数据', '远程数据解析为空');
        parsedData = localPlaylistData;
        remoteDataSuccess = false;
        if (parsedData.playList.isEmpty) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      } else {
        // 合并本地和远程数据
        if (localPlaylistData.playList.isNotEmpty) {
          LogUtil.i('开始合并本地和远程播放列表数据...');
          LogUtil.i('传入合并的列表数量: 2 (本地 + 远程)');
          parsedData = _mergePlaylists([localPlaylistData, remotePlaylistData]);
          
          // 输出合并后的结果
          LogUtil.i('合并后的播放列表:');
          parsedData.playList.forEach((category, groups) {
            if (groups is Map) {
              int channelCount = 0;
              groups.forEach((groupTitle, channels) {
                if (channels is Map) {
                  channelCount += channels.length;
                  // 对于特定频道输出详细信息
                  channels.forEach((channelName, channel) {
                    if (channel is PlayModel && channel.id == 'CCTV1') {
                      LogUtil.i('  CCTV1 在 $category/$groupTitle/$channelName，URLs数量: ${channel.urls?.length ?? 0}');
                    }
                  });
                }
              });
              LogUtil.i('分类 "$category": $channelCount 个频道');
            }
          });
        } else {
          LogUtil.i('本地数据为空，仅使用远程数据');
          parsedData = remotePlaylistData;
        }
      }
    }

    LogUtil.i('解析播放列表: ${parsedData.playList}\n类型: ${parsedData.playList.runtimeType}');
    
    // 处理收藏列表
    final favoritePlaylist = await getOrCreateFavoriteList();
    await updateFavoriteChannelsWithRemoteData(parsedData, PlaylistModel(playList: favoritePlaylist));
    
    // 修复：使用 cast() 方法进行安全类型转换，复用现有逻辑
    try {
      parsedData.playList = _insertFavoritePlaylistFirst(
        parsedData.playList.cast<String, Map<String, Map<String, PlayModel>>>(), 
        PlaylistModel(playList: favoritePlaylist)
      );
    } catch (e, stackTrace) {
      LogUtil.logError('插入收藏列表时类型转换失败', e, stackTrace);
      // 回退：创建空的强类型映射并插入收藏列表
      final emptyPlaylist = <String, Map<String, Map<String, PlayModel>>>{};
      parsedData.playList = _insertFavoritePlaylistFirst(emptyPlaylist, PlaylistModel(playList: favoritePlaylist));
    }
    
    LogUtil.i('合并收藏后播放列表类型: ${parsedData.playList.runtimeType}\n内容: ${parsedData.playList}');

    // 保持原有逻辑：远程数据成功时保存订阅数据
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

  /// 解密 M3U 文件内容（Base64 解码后 XOR 解密）
  static String _decodeEntireFile(String encryptedContent) {
    try {
      // 使用Uint8List进行字节级别操作，提高效率
      final Uint8List decodedBytes = base64Decode(encryptedContent);
      final Uint8List keyBytes = utf8.encode(Config.m3uXorKey);
      final int keyLength = keyBytes.length;
      
      // 直接在字节级别进行XOR操作，避免字符编解码开销
      for (int i = 0; i < decodedBytes.length; i++) {
        decodedBytes[i] = decodedBytes[i] ^ keyBytes[i % keyLength];
      }
      
      return utf8.decode(decodedBytes);
    } catch (e, stackTrace) {
      LogUtil.logError('解密 M3U 文件失败', e, stackTrace);
      return encryptedContent;
    }
  }

  /// 播放列表转换为中文简体或繁体 - 优化版本
  static Future<PlaylistModel> convertPlaylistModel(PlaylistModel data, String conversionType) async {
    try {
      // 映射输入的转换类型字符串到ZhConverter需要的格式
      String converterType;
      if (conversionType == 'zhHans2Hant') {
        converterType = 's2t';  // 简体到繁体
      } else if (conversionType == 'zhHant2Hans') {
        converterType = 't2s';  // 繁体到简体
      } else {
        LogUtil.i('无效的转换类型: $conversionType，跳过转换');
        return data; // 无效转换类型，回退到原始数据
      }

      // 检查 playList 是否为空
      if (data.playList.isEmpty) {
        LogUtil.i('播放列表为空，无需转换');
        return data; // 空播放列表，回退到原始数据
      }

      // 创建 ZhConverter
      final converter = ZhConverter(converterType);
      
      // 确保转换器已初始化，添加超时处理
      try {
        await converter.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('中文转换器初始化超时');
          }
        );
      } catch (e, stackTrace) {
        LogUtil.logError('中文转换器初始化失败', e, stackTrace);
        return data; // 初始化失败，回退到原始数据
      }
      
      // 获取原始播放列表
      final Map<String, dynamic> originalPlayList = data.playList;
      
      // 创建新的播放列表，保持类型一致性
      final Map<String, Map<String, Map<String, PlayModel>>> newPlayList = {};
      
      // 优化点：批量收集需要转换的文本
      final Set<String> textsToConvert = {};
      final Map<String, String> convertCache = {};
      
      // 第一阶段：收集所有需要转换的文本
      for (final categoryEntry in originalPlayList.entries) {
        textsToConvert.add(categoryEntry.key);
        final dynamic groupMapValue = categoryEntry.value;
        
        if (groupMapValue is Map<String, dynamic>) {
          for (final groupEntry in groupMapValue.entries) {
            textsToConvert.add(groupEntry.key);
            final dynamic channelMapValue = groupEntry.value;
            
            if (channelMapValue is Map<String, dynamic>) {
              for (final channelEntry in channelMapValue.entries) {
                textsToConvert.add(channelEntry.key);
                final dynamic playModelValue = channelEntry.value;
                
                if (playModelValue is PlayModel) {
                  if (playModelValue.title?.isNotEmpty ?? false) {
                    textsToConvert.add(playModelValue.title!);
                  }
                  if (playModelValue.group?.isNotEmpty ?? false) {
                    textsToConvert.add(playModelValue.group!);
                  }
                }
              }
            }
          }
        }
      }
      
      // 第二阶段：批量转换文本（优化点：并行处理）
      final List<String> textsList = textsToConvert.toList();
      final int batchSize = 100; // 每批处理100个文本
      
      for (int i = 0; i < textsList.length; i += batchSize) {
        final int end = (i + batchSize < textsList.length) ? i + batchSize : textsList.length;
        final batch = textsList.sublist(i, end);
        
        // 并行转换当前批次
        final futures = batch.map((text) async {
          if (text.isEmpty) return MapEntry(text, text);
          try {
            final converted = await converter.convert(text);
            return MapEntry(text, converted);
          } catch (e) {
            LogUtil.e('转换失败: $text, 错误: $e');
            return MapEntry(text, text);
          }
        });
        
        final results = await Future.wait(futures);
        for (final entry in results) {
          convertCache[entry.key] = entry.value;
        }
      }
      
      // 第三阶段：使用缓存的转换结果构建新的播放列表
      for (final categoryEntry in originalPlayList.entries) {
        final String categoryKey = categoryEntry.key;
        final dynamic groupMapValue = categoryEntry.value;
        
        if (groupMapValue is! Map<String, dynamic>) {
          newPlayList[categoryKey] = <String, Map<String, PlayModel>>{};
          continue;
        }
        
        final String newCategoryKey = convertCache[categoryKey] ?? categoryKey;
        newPlayList[newCategoryKey] = <String, Map<String, PlayModel>>{};
        
        for (final groupEntry in groupMapValue.entries) {
          final String groupKey = groupEntry.key;
          final dynamic channelMapValue = groupEntry.value;
          
          if (channelMapValue is! Map<String, dynamic>) {
            newPlayList[newCategoryKey]![groupKey] = <String, PlayModel>{};
            continue;
          }
          
          final String newGroupKey = convertCache[groupKey] ?? groupKey;
          newPlayList[newCategoryKey]![newGroupKey] = <String, PlayModel>{};
          
          for (final channelEntry in channelMapValue.entries) {
            final String channelKey = channelEntry.key;
            final dynamic playModelValue = channelEntry.value;
            
            if (playModelValue is! PlayModel) {
              continue;
            }
            
            final String newChannelKey = convertCache[channelKey] ?? channelKey;
            final String? newTitle = playModelValue.title != null ? 
                (convertCache[playModelValue.title!] ?? playModelValue.title) : null;
            final String? newGroup = playModelValue.group != null ? 
                (convertCache[playModelValue.group!] ?? playModelValue.group) : null;
            
            final newPlayModel = playModelValue.copyWith(
              title: newTitle,
              group: newGroup
            );
            
            newPlayList[newCategoryKey]![newGroupKey]![newChannelKey] = newPlayModel;
          }
        }
      }
      
      LogUtil.i('中文转换完成: 共转换 ${convertCache.length} 个唯一词条');
      
      // 返回新的PlaylistModel，确保返回类型与原始类型一致
      return PlaylistModel(
        epgUrl: data.epgUrl,
        playList: newPlayList,
      );
    } catch (e, stackTrace) {
      LogUtil.logError('简繁体转换失败，回退到原始数据', e, stackTrace);
      return data; // 异常时回退原始数据
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
      Map<String, Map<String, Map<String, PlayModel>>> favoritePlaylist = favoritePlaylistModel.playList.cast<String, Map<String, Map<String, PlayModel>>>() ?? {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
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
    
    // 优化：提前构建索引映射，减少嵌套循环
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
          // 使用索引直接获取URL，避免重复遍历
          final urls = remoteIdToUrls[favoriteChannel.id!]!;
          final validUrls = urls.where((url) => isLiveLink(url)).toList();
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

/// 合并多个播放列表并去重 - 优化版本
static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
  try {
    // 第一阶段：收集所有频道信息，合并相同 tvg-id 的 URLs
    Map<String, PlayModel> mergedChannelsById = {};
    Map<String, Set<String>> channelLocations = {}; // 记录每个频道出现的位置
    
    // 优化点：使用更高效的URL去重策略
    for (int i = 0; i < playlists.length; i++) {
      PlaylistModel playlist = playlists[i];
      LogUtil.i('处理第 ${i + 1} 个播放列表');
      
      playlist.playList.forEach((category, groups) {
        if (groups is Map) {
          groups.forEach((groupTitle, channels) {
            if (channels is Map) {
              channels.forEach((channelName, channelModel) {
                if (channelModel is PlayModel) {
                  final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
                  final bool hasValidUrls = channelModel.urls != null && channelModel.urls!.isNotEmpty;
                  
                  if (hasValidId && hasValidUrls) {
                    String tvgId = channelModel.id!;
                    String locationKey = '$category|$groupTitle|$channelName';
                    
                    // 记录频道位置
                    channelLocations[tvgId] ??= {};
                    channelLocations[tvgId]!.add(locationKey);
                    
                    if (mergedChannelsById.containsKey(tvgId)) {
                      // 优化点：使用Set进行高效去重
                      Set<String> uniqueUrls = Set<String>.from(mergedChannelsById[tvgId]!.urls ?? []);
                      int urlCountBefore = uniqueUrls.length;
                      uniqueUrls.addAll(channelModel.urls ?? []);
                      int urlCountAfter = uniqueUrls.length;
                      
                      LogUtil.i('合并 $tvgId 的URLs: $urlCountBefore -> $urlCountAfter');
                      mergedChannelsById[tvgId]!.urls = uniqueUrls.toList();
                    } else {
                      // 首次遇到此频道
                      mergedChannelsById[tvgId] = PlayModel(
                        id: channelModel.id,
                        title: channelModel.title,
                        group: channelModel.group,
                        logo: channelModel.logo,
                        urls: List.from(channelModel.urls ?? []),
                      );
                    }
                  }
                }
              });
            }
          });
        }
      });
    }
    
    LogUtil.i('第一阶段完成，共收集 ${mergedChannelsById.length} 个唯一频道');
    
    // 第二阶段：构建最终的播放列表，确保所有位置的频道都使用合并后的 URLs
    PlaylistModel mergedPlaylist = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
    
    for (PlaylistModel playlist in playlists) {
      playlist.playList.forEach((category, groups) {
        if (groups is Map) {
          // 修复：明确指定类型
          mergedPlaylist.playList[category] ??= <String, Map<String, PlayModel>>{};
          
          groups.forEach((groupTitle, channels) {
            if (channels is Map) {
              // 修复：类型安全的访问
              final categoryMap = mergedPlaylist.playList[category] as Map<String, Map<String, PlayModel>>;
              categoryMap[groupTitle] ??= <String, PlayModel>{};
              
              channels.forEach((channelName, channelModel) {
                if (channelModel is PlayModel) {
                  final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
                  
                  if (hasValidId && mergedChannelsById.containsKey(channelModel.id!)) {
                    // 使用合并后的频道信息创建新的 PlayModel
                    PlayModel mergedChannel = mergedChannelsById[channelModel.id!]!;
                    
                    // 修复：类型安全的赋值
                    final groupMap = categoryMap[groupTitle] as Map<String, PlayModel>;
                    groupMap[channelName] = PlayModel(
                      id: mergedChannel.id,
                      title: channelModel.title ?? mergedChannel.title, // 优先使用当前位置的标题
                      group: groupTitle, // 使用当前位置的分组
                      logo: channelModel.logo ?? mergedChannel.logo,
                      urls: List.from(mergedChannel.urls ?? []), // 使用合并后的 URLs
                    );
                  } else if (channelModel.urls != null && channelModel.urls!.isNotEmpty) {
                    // 没有有效ID但有URLs的频道，直接添加
                    final groupMap = categoryMap[groupTitle] as Map<String, PlayModel>;
                    groupMap[channelName] = channelModel;
                    LogUtil.i('添加无ID频道到 $category/$groupTitle/$channelName');
                  }
                }
              });
            }
          });
        }
      });
    }
    
    // 输出合并结果统计
    int totalCategories = mergedPlaylist.playList.length;
    int totalChannels = 0;
    mergedPlaylist.playList.forEach((category, groups) {
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
    
    LogUtil.i('合并完成：共 $totalCategories 个分类，$totalChannels 个频道');
    LogUtil.i('返回播放列表类型: ${mergedPlaylist.playList.runtimeType}');
    
    return mergedPlaylist;
  } catch (e, stackTrace) {
    LogUtil.logError('合并播放列表失败', e, stackTrace);
    // 修复：返回类型安全的空播放列表
    return PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
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

/// 解析 M3U 文件为 PlaylistModel - 优化版本
static Future<PlaylistModel> _parseM3u(String m3u) async {
  try {
    // 优化点：使用流式处理避免大文件内存问题
    final lines = LineSplitter.split(m3u).toList();
    final playListModel = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
    String currentCategory = Config.allChannelsKey;
    String tempGroupTitle = '';
    String tempChannelName = '';

    // 初始化过滤关键字列表
    final List<String> filterKeywords = (Config.cnversion && Config.cnplayListrule.isNotEmpty)
      ? Config.cnplayListrule.split('@')
      : [];
      
    if (filterKeywords.isNotEmpty) {
      LogUtil.i('启用关键字过滤: $filterKeywords');
    }
    
    // 优化点：预编译过滤关键字的小写版本
    final List<String> lowerFilterKeywords = filterKeywords
        .where((k) => k.isNotEmpty)
        .map((k) => k.toLowerCase())
        .toList();
    
    // 改为关键字模糊匹配 - 检查文本是否包含任何过滤关键字
    bool shouldFilter(String text) {
      if (text.isEmpty || lowerFilterKeywords.isEmpty) return false;
      final lowerText = text.toLowerCase();
      return lowerFilterKeywords.any((keyword) => lowerText.contains(keyword));
    }
    
    // 检查是否包含 #CATEGORY 标签
    bool hasCategory = lines.any((line) => line.trim().startsWith('#CATEGORY:'));
    LogUtil.i('M3U 数据 ${hasCategory ? "包含" : "不包含"} #CATEGORY 标签');
    
    // 优化点：预分配当前处理的频道数据
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
          
          // 使用关键字模糊匹配过滤分类
          if (shouldFilter(currentCategory)) {
            LogUtil.i('过滤分类: $currentCategory (关键字匹配)');
            // 跳过此分类的所有内容，直到找到下一个分类标签
            while (i + 1 < lines.length && !lines[i + 1].trim().startsWith('#CATEGORY:')) {
              i++;
            }
            continue;
          }
        } else if (line.startsWith('#EXTINF:')) {
          // 如果当前分类需要被过滤，跳过当前频道
          if (shouldFilter(currentCategory)) {
            continue;
          }

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

          if (tvgId.isEmpty && tvgName.isNotEmpty) tvgId = tvgName;
          if (tvgId.isEmpty) {
            LogUtil.logError('缺少 tvg-id 或 tvg-name', '行内容: $line');
            continue;
          }

          tempGroupTitle = groupTitle;
          tempChannelName = channelName;
          
          // 新增：如果分组需要被过滤，跳过当前频道
          if (shouldFilter(tempGroupTitle)) {
            LogUtil.i('过滤分组: $tempGroupTitle (关键字匹配)');
            continue;
          }
          
          // 优化点：减少重复的Map操作
          if (!playListModel.playList.containsKey(currentCategory)) {
            playListModel.playList[currentCategory] = <String, Map<String, PlayModel>>{};
          }
          final categoryMap = playListModel.playList[currentCategory]!;
          
          if (!categoryMap.containsKey(tempGroupTitle)) {
            categoryMap[tempGroupTitle] = <String, PlayModel>{};
          }
          final groupMap = categoryMap[tempGroupTitle]!;
          
          currentChannel = groupMap[tempChannelName] ??
              PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

          // 优化URL查找，一次性找到下一个有效链接
          bool foundUrl = false;
          for (int j = i + 1; j < lines.length && !foundUrl; j++) {
            final nextLine = lines[j].trim();
            if (nextLine.isEmpty) continue;
            if (nextLine.startsWith('#')) break; // 下一个标签，停止查找
            
            if (isLiveLink(nextLine)) {
              // 修复：添加空安全检查
              if (currentChannel != null) {
                currentChannel.urls ??= [];
                currentChannel.urls!.add(nextLine);
                groupMap[tempChannelName] = currentChannel;
                i = j; // 更新索引到找到的URL位置
                foundUrl = true;
              }
            } else {
              break; // 不是URL且不是标签，停止查找
            }
          }
        } else if (isLiveLink(line)) {
          // 如果当前分类需要被过滤，跳过当前链接
          if (shouldFilter(currentCategory)) {
            continue;
          }
          
          // 如果当前分组需要被过滤，跳过当前链接
          if (shouldFilter(tempGroupTitle)) {
            continue;
          }
          
          // 优化点：减少重复的Map操作
          if (!playListModel.playList.containsKey(currentCategory)) {
            playListModel.playList[currentCategory] = <String, Map<String, PlayModel>>{};
          }
          final categoryMap = playListModel.playList[currentCategory]!;
          
          if (!categoryMap.containsKey(tempGroupTitle)) {
            categoryMap[tempGroupTitle] = <String, PlayModel>{};
          }
          final groupMap = categoryMap[tempGroupTitle]!;
          
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
          
          // 检查当前组是否需要被过滤
          if (shouldFilter(tempGroup)) {
            continue;
          }
          
          if (isLiveLink(channelLink)) {
            // 如果分组名称包含过滤关键字，跳过
            if (shouldFilter(groupTitle)) {
              LogUtil.i('过滤分组: $groupTitle (关键字匹配)');
              continue;
            }
            
            // 优化点：减少重复的Map操作
            if (!playListModel.playList.containsKey(tempGroup)) {
              playListModel.playList[tempGroup] = <String, Map<String, PlayModel>>{};
            }
            final groupMap = playListModel.playList[tempGroup]!;
            
            if (!groupMap.containsKey(groupTitle)) {
              groupMap[groupTitle] = <String, PlayModel>{};
            }
            final channelMap = groupMap[groupTitle]!;
            
            final channel = channelMap[groupTitle] ??
                PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
            channel.urls ??= [];
            if (channelLink.isNotEmpty) channel.urls!.add(channelLink);
            channelMap[groupTitle] = channel;
          } else {
            tempGroup = groupTitle.isEmpty ? '${S.current.defaultText}${i + 1}' : groupTitle;
            
            // 检查新分类是否需要被过滤
            if (shouldFilter(tempGroup)) {
              LogUtil.i('过滤分类: $tempGroup (关键字匹配)');
              continue;  // 跳过初始化这个分类的数据结构
            }
            
            playListModel.playList[tempGroup] ??= <String, Map<String, PlayModel>>{};
          }
        }
      }
    }
    
    // 如果启用了过滤并有过滤规则，记录过滤结果
    if (filterKeywords.isNotEmpty) {
      LogUtil.i('已应用关键字过滤: $filterKeywords');
    }
    
    LogUtil.i('解析完成，播放列表: ${playListModel.playList}');
    return playListModel;
  } catch (e, stackTrace) {
    LogUtil.logError('解析 M3U 文件失败', e, stackTrace);
    return PlaylistModel(playList: {Config.allChannelsKey: <String, Map<String, PlayModel>>{}});
  }
}

  /// 判断链接是否为有效直播链接 - 优化版本
  static bool isLiveLink(String link) {
    // 快速检查，避免不必要的检查
    if (link.isEmpty || link.startsWith('#')) return false;
    
    // 优化点：使用Set查找代替多个startsWith
    for (final prefix in _validUrlPrefixes) {
      if (link.startsWith(prefix)) return true;
    }
    return false;
  }
}
