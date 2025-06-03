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

// 定义转换类型枚举
enum ConversionType {
  zhHans2Hant,
  zhHant2Hans,
}

// 转换类型工厂方法，用于创建 ZhConverter
ZhConverter? createConverter(ConversionType? type) {
  switch (type) {
    case ConversionType.zhHans2Hant:
      return ZhConverter('s2t'); // 简体转繁体
    case ConversionType.zhHant2Hans:
      return ZhConverter('t2s'); // 繁体转简体
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

  // 缓存常用的正则表达式
  static final RegExp extInfRegex = RegExp(r'#EXTINF:-1\s*(?:([^,]*?),)?(.+)', multiLine: true);
  static final RegExp paramRegex = RegExp("(\\w+[-\\w]*)=[\"']?([^\"'\\s]+)[\"']?");
  static final RegExp validBase64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');

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
    LogUtil.i('本地播放列表解析完成:');
    localPlaylistData.playList.forEach((category, groups) {
      if (groups is Map) {
        int channelCount = 0;
        groups.forEach((groupTitle, channels) {
          if (channels is Map) {
            channelCount += channels.length;
          }
        });
        LogUtil.i('  分类 "$category": $channelCount 个频道');
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
        LogUtil.i('检测到多源远程数据，开始合并...');
        remotePlaylistData = await fetchAndMergeM3uData(remoteM3uData) ?? PlaylistModel();
      } else {
        // 处理单源远程数据
        LogUtil.i('处理单源远程数据...');
        remotePlaylistData = await _parseM3u(remoteM3uData);
      }
      
      // 输出远程数据解析结果
      LogUtil.i('远程播放列表解析完成:');
      remotePlaylistData.playList.forEach((category, groups) {
        if (groups is Map) {
          int channelCount = 0;
          groups.forEach((groupTitle, channels) {
            if (channels is Map) {
              channelCount += channels.length;
            }
          });
          LogUtil.i('  分类 "$category": $channelCount 个频道');
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
                      LogUtil.i('    CCTV1 在 $category/$groupTitle/$channelName，URLs数量: ${channel.urls?.length ?? 0}');
                    }
                  });
                }
              });
              LogUtil.i('  分类 "$category": $channelCount 个频道');
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
      
      // 创建转换缓存，避免重复转换相同文本
      final Map<String, String> convertCache = {};
      int convertCount = 0;
      
      // 转换文本的辅助函数，带缓存
      Future<String> convertText(String text) async {
        if (text.isEmpty) return text;
        
        // 检查缓存
        if (convertCache.containsKey(text)) {
          return convertCache[text]!;
        }
        
        try {
          final converted = await converter.convert(text);
          convertCache[text] = converted;
          if (converted != text) convertCount++;
          return converted;
        } catch (e) {
          LogUtil.e('转换失败: $text, 错误: $e');
          return text; // 失败时返回原文本
        }
      }
      
      // 🎯 优化：简化处理逻辑，移除过度复杂的批处理
      // 顺序处理所有分类，避免过度并发控制的调度开销
      for (final categoryEntry in originalPlayList.entries) {
        final String categoryKey = categoryEntry.key;
        final dynamic groupMapValue = categoryEntry.value;
        
        // 类型检查：先验证类型再进行转换，避免运行时错误
        if (groupMapValue is! Map<String, dynamic>) {
          newPlayList[categoryKey] = <String, Map<String, PlayModel>>{};
          continue;
        }
        
        final Map<String, dynamic> groupMap = groupMapValue;
        
        // 转换分类键名(categoryKey)，不为空时转换
        String newCategoryKey = categoryKey.isNotEmpty ? await convertText(categoryKey) : categoryKey;
        
        // 确保新类别键存在
        newPlayList[newCategoryKey] = <String, Map<String, PlayModel>>{};
        
        // 处理分组 - 简化处理逻辑
        for (final groupEntry in groupMap.entries) {
          final String groupKey = groupEntry.key;
          final dynamic channelMapValue = groupEntry.value;
          
          // 类型检查
          if (channelMapValue is! Map<String, dynamic>) {
            newPlayList[newCategoryKey]![groupKey] = <String, PlayModel>{};
            continue;
          }
          
          final Map<String, dynamic> channelMap = channelMapValue;
          
          // 转换分组键名(groupKey)，不为空时转换
          String newGroupKey = groupKey.isNotEmpty ? await convertText(groupKey) : groupKey;
          
          // 确保新分组键存在
          newPlayList[newCategoryKey]![newGroupKey] = <String, PlayModel>{};
          
          // 🎯 优化：直接处理频道，移除不必要的批处理复杂度
          for (final channelEntry in channelMap.entries) {
            final String channelKey = channelEntry.key;
            final dynamic playModelValue = channelEntry.value;
            
            // 类型检查与安全转换
            if (playModelValue is! PlayModel) {
              continue;
            }
            
            final PlayModel playModel = playModelValue;
            
            // 🎯 优化：批量收集需要转换的文本，减少await调用
            final List<String> textsToConvert = [];
            final List<String> originalTexts = [];
            
            // 收集需要转换的文本
            if (channelKey.isNotEmpty) {
              textsToConvert.add(channelKey);
              originalTexts.add('channelKey');
            }
            if (playModel.title != null && playModel.title!.isNotEmpty) {
              textsToConvert.add(playModel.title!);
              originalTexts.add('title');
            }
            if (playModel.group != null && playModel.group!.isNotEmpty) {
              textsToConvert.add(playModel.group!);
              originalTexts.add('group');
            }
            
            // 批量转换文本
            final List<String> convertedTexts = [];
            for (final text in textsToConvert) {
              convertedTexts.add(await convertText(text));
            }
            
            // 应用转换结果
            String newChannelKey = channelKey;
            String? newTitle = playModel.title;
            String? newGroup = playModel.group;
            
            int convertIndex = 0;
            for (int i = 0; i < originalTexts.length; i++) {
              switch (originalTexts[i]) {
                case 'channelKey':
                  newChannelKey = convertedTexts[convertIndex];
                  break;
                case 'title':
                  newTitle = convertedTexts[convertIndex];
                  break;
                case 'group':
                  newGroup = convertedTexts[convertIndex];
                  break;
              }
              convertIndex++;
            }
            
            // 创建新的PlayModel，使用copyWith确保对象属性正确复制
            final newPlayModel = playModel.copyWith(
              title: newTitle,
              group: newGroup
            );
            
            newPlayList[newCategoryKey]![newGroupKey]![newChannelKey] = newPlayModel;
          }
        }
      }
      
      LogUtil.i('中文转换完成: 共转换 $convertCount 个词条');
      
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
    LogUtil.i('开始合并播放列表，共 ${playlists.length} 个列表');
    
    // 🎯 优化：一次遍历完成合并，避免两阶段处理的重复遍历
    PlaylistModel mergedPlaylist = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
    Map<String, PlayModel> mergedChannelsById = {}; // 用于ID去重
    
    for (int i = 0; i < playlists.length; i++) {
      PlaylistModel playlist = playlists[i];
      LogUtil.i('处理第 ${i + 1} 个播放列表');
      
      playlist.playList.forEach((category, groups) {
        if (groups is Map) {
          // 🎯 优化：明确类型转换，减少重复类型检查
          mergedPlaylist.playList[category] ??= <String, Map<String, PlayModel>>{};
          final categoryMap = mergedPlaylist.playList[category] as Map<String, Map<String, PlayModel>>;
          
          groups.forEach((groupTitle, channels) {
            if (channels is Map) {
              categoryMap[groupTitle] ??= <String, PlayModel>{};
              final groupMap = categoryMap[groupTitle];
              
              channels.forEach((channelName, channelModel) {
                if (channelModel is PlayModel) {
                  final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
                  final bool hasValidUrls = channelModel.urls != null && channelModel.urls!.isNotEmpty;
                  
                  if (hasValidId && hasValidUrls) {
                    String tvgId = channelModel.id!;
                    
                    if (mergedChannelsById.containsKey(tvgId)) {
                      // 🎯 优化：使用LinkedHashSet去重，保持顺序
                      LinkedHashSet<String> uniqueUrls = LinkedHashSet<String>.from(mergedChannelsById[tvgId]!.urls ?? []);
                      int urlCountBefore = uniqueUrls.length;
                      uniqueUrls.addAll(channelModel.urls ?? []);
                      int urlCountAfter = uniqueUrls.length;
                      
                      LogUtil.i('合并 $tvgId 的URLs: $urlCountBefore -> $urlCountAfter');
                      
                      // 更新已存在频道的URLs
                      mergedChannelsById[tvgId]!.urls = uniqueUrls.toList();
                      
                      // 同时更新当前位置的频道信息，使用合并后的URLs
                      groupMap[channelName] = PlayModel(
                        id: channelModel.id,
                        title: channelModel.title,
                        group: groupTitle,
                        logo: channelModel.logo,
                        urls: List.from(uniqueUrls),
                      );
                    } else {
                      // 首次遇到此频道
                      final newChannel = PlayModel(
                        id: channelModel.id,
                        title: channelModel.title,
                        group: groupTitle,
                        logo: channelModel.logo,
                        urls: List.from(channelModel.urls ?? []),
                      );
                      
                      mergedChannelsById[tvgId] = newChannel;
                      groupMap[channelName] = newChannel;
                      
                      LogUtil.i('新增频道 $tvgId，初始URLs数量: ${channelModel.urls?.length ?? 0}');
                    }
                  } else if (hasValidUrls) {
                    // 没有有效ID但有URLs的频道，直接添加
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
    // 🎯 修复：返回类型安全的空播放列表
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

/// 解析 M3U 文件为 PlaylistModel
static Future<PlaylistModel> _parseM3u(String m3u) async {
  try {
    final lines = m3u.split(RegExp(r'\r?\n'));
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
    
    // 改为关键字模糊匹配 - 检查文本是否包含任何过滤关键字
    bool shouldFilter(String text) {
      if (text.isEmpty || filterKeywords.isEmpty) return false;
      return filterKeywords.any((keyword) => 
        keyword.isNotEmpty && text.toLowerCase().contains(keyword.toLowerCase()));
    }
    
    // 检查是否包含 #CATEGORY 标签
    bool hasCategory = lines.any((line) => line.trim().startsWith('#CATEGORY:'));
    LogUtil.i('M3U 数据 ${hasCategory ? "包含" : "不包含"} #CATEGORY 标签');
    
    // 🎯 优化：预处理lines，避免重复trim操作
    final List<String> trimmedLines = lines.map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    
    if (m3u.startsWith('#EXTM3U') || m3u.startsWith('#EXTINF')) {
      for (int i = 0; i < trimmedLines.length; i++) {
        String line = trimmedLines[i];
        
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
            while (i + 1 < trimmedLines.length && !trimmedLines[i + 1].startsWith('#CATEGORY:')) {
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
          
          // 新增：如果分组需要被过滤，跳过当前频道
          if (shouldFilter(tempGroupTitle)) {
            LogUtil.i('过滤分组: $tempGroupTitle (关键字匹配)');
            continue;
          }
          
          playListModel.playList[currentCategory] ??= <String, Map<String, PlayModel>>{};
          playListModel.playList[currentCategory][tempGroupTitle] ??= <String, PlayModel>{};
          PlayModel channel = playListModel.playList[currentCategory][tempGroupTitle][tempChannelName] ??
              PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

          // 🎯 优化：一次性查找所有后续URL，避免重复扫描
          for (int j = i + 1; j < trimmedLines.length; j++) {
            final nextLine = trimmedLines[j];
            if (nextLine.startsWith('#')) {
              i = j - 1; // 回退到标签前，下次循环会处理这个标签
              break;
            }
            
            if (isLiveLink(nextLine)) {
              channel.urls ??= [];
              channel.urls!.add(nextLine);
              i = j; // 更新索引到当前URL位置
            } else {
              i = j - 1; // 回退，准备处理下一行
              break;
            }
          }
          
          if (channel.urls != null && channel.urls!.isNotEmpty) {
            playListModel.playList[currentCategory][tempGroupTitle][tempChannelName] = channel;
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
          
          playListModel.playList[currentCategory] ??= <String, Map<String, PlayModel>>{};
          playListModel.playList[currentCategory][tempGroupTitle] ??= <String, PlayModel>{};
          playListModel.playList[currentCategory][tempGroupTitle][tempChannelName] ??=
              PlayModel(id: '', group: tempGroupTitle, title: tempChannelName, urls: []);
          playListModel.playList[currentCategory][tempGroupTitle][tempChannelName]!.urls ??= [];
          playListModel.playList[currentCategory][tempGroupTitle][tempChannelName]!.urls!.add(line);
        }
      }
    } else {
      String tempGroup = S.current.defaultText;
      for (int i = 0; i < trimmedLines.length; i++) {
        final line = trimmedLines[i];
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
            
            playListModel.playList[tempGroup] ??= <String, Map<String, PlayModel>>{};
            playListModel.playList[tempGroup][groupTitle] ??= <String, PlayModel>{};
            final channel = playListModel.playList[tempGroup][groupTitle][groupTitle] ??
                PlayModel(group: tempGroup, id: groupTitle, title: groupTitle, urls: []);
            channel.urls ??= [];
            if (channelLink.isNotEmpty) channel.urls!.add(channelLink);
            playListModel.playList[tempGroup][groupTitle][groupTitle] = channel;
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

  /// 判断链接是否为有效直播链接
  static bool isLiveLink(String link) {
    // 快速检查，避免不必要的正则匹配
    if (link.isEmpty || link.startsWith('#')) return false;
    
    // 使用直接的字符串检查代替正则表达式提高性能
    return link.startsWith('http://') || 
           link.startsWith('https://') || 
           link.startsWith('rtmp://') || 
           link.startsWith('rtsp://') || 
           link.startsWith('mms://') || 
           link.startsWith('ftp://');
  }
}
