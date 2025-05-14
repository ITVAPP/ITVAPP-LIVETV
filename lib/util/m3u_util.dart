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
        if (parsedData.playList.isEmpty) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      } else {
        parsedData = m3uData.contains('||') ? await fetchAndMergeM3uData(m3uData) ?? PlaylistModel() : await _parseM3u(m3uData);
        if (parsedData.playList.isEmpty) {
          return M3uResult(errorMessage: S.current.getm3udataerror, errorType: ErrorType.parseError);
        }
      }

      LogUtil.i('解析播放列表: ${parsedData.playList}\n类型: ${parsedData.playList.runtimeType}');
      final favoritePlaylist = await getOrCreateFavoriteList();
      await updateFavoriteChannelsWithRemoteData(parsedData, PlaylistModel(playList: favoritePlaylist));
      parsedData.playList = _insertFavoritePlaylistFirst(parsedData.playList as Map<String, Map<String, Map<String, PlayModel>>>, PlaylistModel(playList: favoritePlaylist));
      LogUtil.i('合并收藏后播放列表类型: ${parsedData.playList.runtimeType}\n内容: ${parsedData.playList}');

      // 修复逻辑错误：!m3uData.isEmpty 改为 m3uData.isNotEmpty
      if (m3uData.isNotEmpty) {
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
      // 增强健壮性：检查输入是否为有效的Base64字符串
      if (encryptedContent.isEmpty || !validBase64Regex.hasMatch(encryptedContent)) {
        LogUtil.logError('解密失败', '无效的 Base64 字符串');
        return encryptedContent;
      }
      
      // 优化：使用Uint8List进行字节级别操作，提高效率
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

  /// 播放列表转换为中文简体或繁体
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
      
      // 优化批处理函数：使用泛型和更高效的队列处理
      Future<List<T>> processBatch<T>(List<Future<T> Function()> tasks, int batchSize) async {
        final results = <T>[];
        for (int i = 0; i < tasks.length; i += batchSize) {
          final end = (i + batchSize < tasks.length) ? i + batchSize : tasks.length;
          final batchTasks = tasks.sublist(i, end);
          final batchResults = await Future.wait(batchTasks.map((task) => task()));
          results.addAll(batchResults);
        }
        return results;
      }
      
      // 处理分类的异步任务队列
      final categoryTasks = <Future<void> Function()>[];
      
      // 处理所有分类
      for (final categoryEntry in originalPlayList.entries) {
        categoryTasks.add(() async {
          final String categoryKey = categoryEntry.key;
          final dynamic groupMapValue = categoryEntry.value;
          
          // 改进类型检查：先验证类型再进行转换，避免运行时错误
          if (groupMapValue is! Map<String, dynamic>) {
            newPlayList[categoryKey] = <String, Map<String, PlayModel>>{};
            return;
          }
          
          final Map<String, dynamic> groupMap = groupMapValue;
          
          // 转换分类键名(categoryKey)，不为空时转换
          String newCategoryKey = categoryKey.isNotEmpty ? await convertText(categoryKey) : categoryKey;
          
          // 确保新类别键存在
          newPlayList[newCategoryKey] = <String, Map<String, PlayModel>>{};
          
          // 处理分组的异步任务队列
          final groupTasks = <Future<void> Function()>[];
          
          // 处理分组
          for (final groupEntry in groupMap.entries) {
            groupTasks.add(() async {
              final String groupKey = groupEntry.key;
              final dynamic channelMapValue = groupEntry.value;
              
              // 改进类型检查
              if (channelMapValue is! Map<String, dynamic>) {
                newPlayList[newCategoryKey]![groupKey] = <String, PlayModel>{};
                return;
              }
              
              final Map<String, dynamic> channelMap = channelMapValue;
              
              // 转换分组键名(groupKey)，不为空时转换
              String newGroupKey = groupKey.isNotEmpty ? await convertText(groupKey) : groupKey;
              
              // 确保新分组键存在
              newPlayList[newCategoryKey]![newGroupKey] = <String, PlayModel>{};
              
              // 优化：收集所有频道条目，分批处理
              final channelEntries = channelMap.entries.toList();
              final int totalChannels = channelEntries.length;
              
              // 优化批量处理大小，根据实际情况调整
              final int channelBatchSize = 50; // 每批处理50个频道
              
              // 分批处理频道
              for (int i = 0; i < totalChannels; i += channelBatchSize) {
                final int end = (i + channelBatchSize < totalChannels) ? i + channelBatchSize : totalChannels;
                final batchChannelEntries = channelEntries.sublist(i, end);
                
                // 创建频道处理任务
                final channelTasks = <Future<MapEntry<String, PlayModel>> Function()>[];
                
                for (final channelEntry in batchChannelEntries) {
                  channelTasks.add(() async {
                    final String channelKey = channelEntry.key;
                    final dynamic playModelValue = channelEntry.value;
                    
                    // 类型检查与安全转换
                    if (playModelValue is! PlayModel) {
                      return MapEntry(channelKey, playModelValue as PlayModel);
                    }
                    
                    final PlayModel playModel = playModelValue;
                    
                    // 转换频道键名(channelKey)，不为空时转换
                    String newChannelKey = channelKey.isNotEmpty ? await convertText(channelKey) : channelKey;
                    
                    // 转换标题
                    String? newTitle = playModel.title;
                    if (newTitle != null && newTitle.isNotEmpty) {
                      newTitle = await convertText(newTitle);
                    }
                    
                    // 转换分组
                    String? newGroup = playModel.group;
                    if (newGroup != null && newGroup.isNotEmpty) {
                      newGroup = await convertText(newGroup);
                    }
                    
                    // 创建新的PlayModel，使用copyWith确保对象属性正确复制
                    final newPlayModel = playModel.copyWith(
                      title: newTitle,
                      group: newGroup
                    );
                    
                    return MapEntry(newChannelKey, newPlayModel);
                  });
                }
                
                // 优化：并行处理一批频道，限制合理的并发数
                final channelResults = await processBatch(channelTasks, 20);
                
                // 将处理结果添加到新的播放列表
                for (final entry in channelResults) {
                  if (entry != null) {
                    newPlayList[newCategoryKey]![newGroupKey]![entry.key] = entry.value;
                  }
                }
              }
            });
          }
          
          // 并行处理分组，限制合理的并发数
          await processBatch(groupTasks, 10);
        });
      }
      
      // 并行处理分类，限制合理的并发数
      await processBatch(categoryTasks, 5);
      
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

  /// 合并多个播放列表并去重
  static PlaylistModel _mergePlaylists(List<PlaylistModel> playlists) {
    try {
      PlaylistModel mergedPlaylist = PlaylistModel()..playList = {};
      Map<String, PlayModel> mergedChannelsById = {};
      for (PlaylistModel playlist in playlists) {
        playlist.playList.forEach((category, groups) {
          if (groups is Map) {
            mergedPlaylist.playList[category] ??= {};
            groups.forEach((groupTitle, channels) {
              if (channels is Map) {
                mergedPlaylist.playList[category][groupTitle] ??= {};
                channels.forEach((channelName, channelModel) {
                  if (channelModel is PlayModel) {
                    final bool hasValidId = channelModel.id != null && channelModel.id!.isNotEmpty;
                    final bool hasValidUrls = channelModel.urls != null && channelModel.urls!.isNotEmpty;
                    
                    if (hasValidId && hasValidUrls) {
                      String tvgId = channelModel.id!;
                      if (mergedChannelsById.containsKey(tvgId)) {
                        LinkedHashSet<String> uniqueUrls = LinkedHashSet<String>.from(mergedChannelsById[tvgId]!.urls ?? []);
                        uniqueUrls.addAll(channelModel.urls ?? []);
                        mergedChannelsById[tvgId]!.urls = uniqueUrls.toList();
                      } else {
                        mergedChannelsById[tvgId] = channelModel;
                      }
                      (mergedPlaylist.playList[category][groupTitle] as Map)[channelName] = mergedChannelsById[tvgId]!;
                    }
                  }
                });
              }
            });
          }
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

/// 解析 M3U 文件为 PlaylistModel
static Future<PlaylistModel> _parseM3u(String m3u) async {
  try {
    final lines = m3u.split(RegExp(r'\r?\n'));
    final playListModel = PlaylistModel()..playList = <String, Map<String, Map<String, PlayModel>>>{};
    String currentCategory = Config.allChannelsKey;
    String tempGroupTitle = '';
    String tempChannelName = '';

    // 初始化过滤规则 - 预处理为Set提高查找效率
    final Set<String> filteredCategoriesSet = (Config.cnversion && Config.cnplayListrule.isNotEmpty)
      ? Set.from(Config.cnplayListrule.split('@'))
      : {};
    
    // 检查当前分类是否需要被过滤的辅助函数 - 使用Set查找更高效
    bool shouldFilterCategory(String category) {
      return filteredCategoriesSet.contains(category);
    }

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
          
          // 如果当前分类需要被过滤，跳到下一个分类标签
          if (shouldFilterCategory(currentCategory)) {
            LogUtil.i('过滤分类: $currentCategory');
            // 跳过此分类的所有内容，直到找到下一个分类标签
            while (i + 1 < lines.length && !lines[i + 1].trim().startsWith('#CATEGORY:')) {
              i++;
            }
            continue;
          }
        } else if (line.startsWith('#EXTINF:')) {
          // 如果当前分类需要被过滤，跳过当前频道
          if (shouldFilterCategory(currentCategory)) {
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
          playListModel.playList[currentCategory] ??= <String, Map<String, PlayModel>>{};
          playListModel.playList[currentCategory][tempGroupTitle] ??= <String, PlayModel>{};
          PlayModel channel = playListModel.playList[currentCategory][tempGroupTitle][tempChannelName] ??
              PlayModel(id: tvgId, group: tempGroupTitle, logo: tvgLogo, title: tempChannelName, urls: []);

          // 优化URL查找，一次性找到下一个有效链接
          bool foundUrl = false;
          for (int j = i + 1; j < lines.length && !foundUrl; j++) {
            final nextLine = lines[j].trim();
            if (nextLine.isEmpty) continue;
            if (nextLine.startsWith('#')) break; // 下一个标签，停止查找
            
            if (isLiveLink(nextLine)) {
              channel.urls ??= [];
              channel.urls!.add(nextLine);
              playListModel.playList[currentCategory][tempGroupTitle][tempChannelName] = channel;
              i = j; // 更新索引到找到的URL位置
              foundUrl = true;
            } else {
              break; // 不是URL且不是标签，停止查找
            }
          }
        } else if (isLiveLink(line)) {
          // 如果当前分类需要被过滤，跳过当前链接
          if (shouldFilterCategory(currentCategory)) {
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
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final lineList = line.split(',');
        if (lineList.length >= 2) {
          final groupTitle = lineList[0];
          final channelLink = lineList[1];
          
          // 检查当前组是否需要被过滤
          if (shouldFilterCategory(tempGroup)) {
            continue;
          }
          
          if (isLiveLink(channelLink)) {
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
            if (shouldFilterCategory(tempGroup)) {
              LogUtil.i('过滤分类: $tempGroup');
              continue;  // 跳过初始化这个分类的数据结构
            }
            
            playListModel.playList[tempGroup] ??= <String, Map<String, PlayModel>>{};
          }
        }
      }
    }
    
    // 如果启用了过滤并有过滤规则，记录过滤结果
    if (filteredCategoriesSet.isNotEmpty) {
      LogUtil.i('已应用分类过滤规则，过滤的分类: $filteredCategoriesSet');
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
