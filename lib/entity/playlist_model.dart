import 'dart:convert';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// 构造函数，用于创建一个 [PlaylistModel] 实例。
/// [epgUrl] 是一个可选的字符串，指向EPG数据源的URL。
/// [playList] 是一个三层嵌套的Map，其中：
/// - 第一层 `String` 键是分类（例如："区域"或"语言"）
///   - 示例：对于 M3U 中未指定分类信息的情况，使用默认分类。
///   - 从 M3U 文件的 `#EXTINF` 标签中，如果没有独立的分类标签，使用默认分类。
/// - 第二层 `String` 键是组的标题（例如："体育"，"新闻"），从 `group-title` 提取。
///   - 示例：`group-title="央视频道"`，提取 "央视频道" 作为第二层键。
/// - 第三层 `Map` 将频道名称（`String`）与对应的 [PlayModel] 实例关联。
///   - 示例：`CCTV-1 综合` 作为第三层键，值是 `PlayModel` 对象。
/// 
/// ### M3U 播放列表示例：
/// #EXTM3U x-tvg-url=" http://example.com/e.xml"
///
/// #CATEGORY:央视频道
/// #EXTINF:-1 tvg-id="CCTV1" tvg-name="CCTV-1 综合" tvg-logo=" http://example.com/CCTV1.png" group-title="央视频道",CCTV-1 综合
/// http://example.com/cctv1.m3u8
/// 
/// #CATEGORY:央视频道
/// #EXTINF:-1 tvg-id="CCTV2" tvg-name="CCTV-2 财经" tvg-logo=" http://example.com/CCTV2.png" group-title="央视频道",CCTV-2 财经
/// http://example.com/cctv2.m3u8
///
/// #CATEGORY:娱乐频道
/// #EXTINF:-1 tvg-id="HunanTV" tvg-name="湖南卫视" tvg-logo=" http://example.com/HunanTV.png" group-title="娱乐频道",湖南卫视
/// http://example.com/hunantv.m3u8
///
/// #CATEGORY:体育频道
/// #EXTINF:-1 tvg-id="CCTV5" tvg-name="CCTV-5 体育" tvg-logo=" http://example.com/CCTV5.png" group-title="体育频道",CCTV-5 体育
/// http://example.com/cctv5.m3u8
/// ```

// 播放列表模型，管理EPG和频道
class PlaylistModel {
  PlaylistModel({
    this.epgUrl,
    Map<String, dynamic>? playList,
  }) : playList = playList ?? {}, 
       _cachedChannels = null,  // 初始化缓存
       _needRebuildCache = true, // 初始化缓存标记
       _groupChannelIndex = null, // 初始化组-频道索引
       _idChannelIndex = null,  // 初始化ID-频道索引
       _searchCache = {}; // 初始化搜索缓存

  // EPG节目指南URL
  String? epgUrl;

  // 播放列表，支持两层或三层结构
  Map<String, dynamic> playList;

  // 频道缓存
  List<PlayModel>? _cachedChannels;
  bool _needRebuildCache = true;
  
  // 组和ID索引
  Map<String, Map<String, PlayModel>>? _groupChannelIndex;
  Map<String, PlayModel>? _idChannelIndex;
  
  // 搜索结果缓存
  final Map<String, List<PlayModel>> _searchCache;
  static const int _maxSearchCacheSize = 50; // 缓存最大容量

  // 从JSON解析播放列表
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return _tryParseJson(() {
      LogUtil.i('[PlaylistModel] 解析JSON数据: ${json.keys}');
      String? epgUrl = json['epgUrl'] as String?;
      Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>? ?? {};
      Map<String, dynamic> playList = playListJson.isNotEmpty ? _parsePlayList(playListJson) : {};
      
      final model = PlaylistModel(epgUrl: epgUrl, playList: playList);
      if (playList.isNotEmpty) {
        model._buildIndices();
        model._needRebuildCache = true; // 标记需要构建频道缓存
      }
      return model;
    }, '[PlaylistModel] 解析JSON出错');
  }

  // 从字符串解析播放列表
  static PlaylistModel fromString(String data) {
    return _tryParseJson(() {
      LogUtil.i('[PlaylistModel] 解析字符串数据: 长度${data.length}');
      final Map<String, dynamic> jsonData = jsonDecode(data);
      return PlaylistModel.fromJson(jsonData);
    }, '[PlaylistModel] 解析字符串出错');
  }

  // 判断是否为三层结构
  static bool _isThreeLayerStructure(Map<String, dynamic> json) {
    if (json.isEmpty) return false;
    for (var firstValue in json.values) {
      if (firstValue is! Map) continue;
      if (firstValue.isEmpty) continue;
      for (var secondValue in firstValue.values) {
        if (secondValue is Map) return true;
      }
    }
    return false;
  }

  // 转换为JSON字符串
  @override
  String toString() {
    try {
      if (playList.isNotEmpty) {
        for (var category in playList.entries) {
          final groups = category.value;
          if (groups is Map<String, dynamic>) {
            for (var groupEntry in groups.entries) {
              final channels = groupEntry.value;
              if (channels is Map<String, dynamic>) {
                for (var channelEntry in channels.entries) {
                  final channelName = channelEntry.key;
                  final channel = channelEntry.value;
                  if (channel is PlayModel) {
                    if (channel.id == null || channel.id!.isEmpty) {
                      channel.id = channelName;
                    }
                  }
                }
              }
            }
          }
        }
      }
      return jsonEncode({'epgUrl': epgUrl, 'playList': playList});
    } catch (e, stackTrace) {
      LogUtil.logError('[PlaylistModel] 转换JSON字符串出错', e, stackTrace);
      return '{"epgUrl": null, "playList": {}}';
    }
  }

  // 解析播放列表，支持两层或三层结构
  static Map<String, dynamic> _parsePlayList(Map<String, dynamic> json) {
    try {
      LogUtil.i('[PlaylistModel] 解析播放列表: ${json.keys}');
      if (json.isEmpty) {
        LogUtil.i('[PlaylistModel] 空播放列表，返回默认结构');
        return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
      }
      Map<String, dynamic> sanitizedJson = {};
      json.forEach((key, value) {
        sanitizedJson[key.toString()] = value;
      });
      if (_isThreeLayerStructure(sanitizedJson)) {
        LogUtil.i('[PlaylistModel] 处理三层结构');
        return _parseThreeLayer(sanitizedJson);
      }
      LogUtil.i('[PlaylistModel] 处理两层结构，转换为三层');
      return _parseThreeLayer({Config.allChannelsKey: _parseTwoLayer(sanitizedJson)});
    } catch (e, stackTrace) {
      LogUtil.logError('[PlaylistModel] 解析播放列表出错', e, stackTrace);
      return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
    }
  }

  // 通过索引获取指定频道
  PlayModel? getChannel(dynamic categoryOrGroup, String groupOrChannel, [String? channel]) {
    // 优化：只在索引不存在时构建
    if (_groupChannelIndex == null || _idChannelIndex == null) {
      _buildIndices();
    }
    
    if (channel == null && categoryOrGroup is String) {
      String group = categoryOrGroup;
      String channelName = groupOrChannel;
      return _groupChannelIndex?[group]?[channelName];
    } else if (channel != null && categoryOrGroup is String) {
      String category = categoryOrGroup;
      String group = groupOrChannel;
      
      var indexedChannel = _groupChannelIndex?[group]?[channel];
      if (indexedChannel != null) return indexedChannel;
      
      var categoryMap = playList[category];
      if (categoryMap is Map) {
        var groupMap = categoryMap[group];
        if (groupMap is Map) {
          var foundChannel = groupMap[channel];
          if (foundChannel is PlayModel) {
            return foundChannel;
          }
        }
      }
    }
    return null;
  }
  
  // 构建组和ID索引
  void _buildIndices() {
    _groupChannelIndex = {};
    _idChannelIndex = {};
    
    for (var categoryEntry in playList.entries) {
      final categoryMap = categoryEntry.value;
      if (categoryMap is! Map<String, dynamic>) continue;
      
      for (var groupEntry in categoryMap.entries) {
        final groupName = groupEntry.key;
        final channels = groupEntry.value;
        
        if (channels is! Map<String, dynamic>) continue;
        
        if (!_groupChannelIndex!.containsKey(groupName)) {
          _groupChannelIndex![groupName] = {};
        }
        
        for (var channelEntry in channels.entries) {
          final channelName = channelEntry.key;
          final channel = channelEntry.value;
          
          if (channel is PlayModel) {
            _groupChannelIndex![groupName]![channelName] = channel;
            if (channel.id != null && channel.id!.isNotEmpty) {
              _idChannelIndex![channel.id!] = channel;
            }
          }
        }
      }
    }
  }

  // 解析三层结构播放列表
  static Map<String, Map<String, Map<String, PlayModel>>> _parseThreeLayer(Map<String, dynamic> json) {
    Map<String, Map<String, Map<String, PlayModel>>> result = {};
    try {
      for (var entry in json.entries) {
        String category = entry.key.isNotEmpty ? entry.key : Config.allChannelsKey;
        var groupMapJson = entry.value;
        if (groupMapJson is! Map) {
          LogUtil.i('[PlaylistModel] 跳过无效组: $category');
          continue;
        }
        // 优化：直接处理，避免额外的函数调用
        Map<String, Map<String, PlayModel>> groupMapResult = {};
        for (var groupEntry in groupMapJson.entries) {
          String groupTitle = groupEntry.key.toString();
          var channelMapJson = groupEntry.value;
          if (channelMapJson is! Map) {
            LogUtil.i('[PlaylistModel] 跳过无效频道: $groupTitle');
            continue;
          }
          Map<String, PlayModel> channels = {};
          for (var channelEntry in channelMapJson.entries) {
            String channelName = channelEntry.key.toString();
            var channelData = channelEntry.value;
            channels[channelName] = channelData is Map<String, dynamic>
                ? PlayModel.fromJson(channelData)
                : PlayModel();
          }
          groupMapResult[groupTitle] = channels;
        }
        result[category] = groupMapResult;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('[PlaylistModel] 解析三层结构出错', e, stackTrace);
    }
    return result.isEmpty ? {Config.allChannelsKey: <String, Map<String, PlayModel>>{}} : result;
  }

  // 解析两层结构播放列表
  static Map<String, Map<String, PlayModel>> _parseTwoLayer(Map<String, dynamic> json) {
    Map<String, Map<String, PlayModel>> result = {};
    try {
      json.forEach((groupTitle, channelMapJson) {
        String sanitizedGroupTitle = groupTitle.toString();
        if (channelMapJson is! Map) {
          LogUtil.i('[PlaylistModel] 跳过无效频道: $sanitizedGroupTitle');
          return;
        }
        Map<String, PlayModel> channels = {};
        channelMapJson.forEach((channelName, channelData) {
          String sanitizedChannelName = channelName.toString();
          channels[sanitizedChannelName] = channelData is Map<String, dynamic>
              ? PlayModel.fromJson(channelData)
              : PlayModel();
        });
        result[sanitizedGroupTitle] = channels;
      });
    } catch (e, stackTrace) {
      LogUtil.logError('[PlaylistModel] 解析两层结构出错', e, stackTrace);
    }
    return result.isEmpty ? <String, Map<String, PlayModel>>{} : result;
  }

  // 搜索匹配关键字的频道（优化版）
  List<PlayModel> searchChannels(String keyword) {
    // 优化：检查缓存
    if (_searchCache.containsKey(keyword)) {
      return List.from(_searchCache[keyword]!);
    }
    
    // 优化：延迟构建频道缓存，只在真正需要时构建
    if (_cachedChannels == null || _needRebuildCache) {
      _buildChannelCache();
    }
    
    final String lowerKeyword = keyword.toLowerCase();
    final results = _cachedChannels!.where((channel) =>
        (channel.title?.toLowerCase().contains(lowerKeyword) ?? false) ||
        (channel.group?.toLowerCase().contains(lowerKeyword) ?? false)).toList();
    
    // 缓存搜索结果，控制内存
    if (_searchCache.length >= _maxSearchCacheSize) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[keyword] = List.from(results);
    
    return results;
  }
  
  // 构建频道缓存（从 searchChannels 中提取的优化方法）
  void _buildChannelCache() {
    // 优化：先确保索引已构建
    if (_groupChannelIndex == null || _idChannelIndex == null) {
      _buildIndices();
    }
    
    _cachedChannels = [];
    final Set<String> seenIds = {};
    
    // 优化：使用单次遍历构建缓存
    for (var categoryEntry in playList.entries) {
      final categoryValue = categoryEntry.value;
      if (categoryValue is! Map) continue;
      
      for (var groupEntry in categoryValue.entries) {
        final groupValue = groupEntry.value;
        if (groupValue is! Map) continue;
        
        for (var channelEntry in groupValue.entries) {
          final channel = channelEntry.value;
          if (channel is PlayModel) {
            // 保持原始逻辑：使用 channel.id 或 channelEntry.key 作为唯一标识
            final channelId = channel.id ?? channelEntry.key;
            if (!seenIds.contains(channelId)) {
              seenIds.add(channelId);
              _cachedChannels!.add(channel);
            }
          }
        }
      }
    }
    
    _needRebuildCache = false;
  }

  // 标记缓存需重建
  void invalidateCache() {
    _needRebuildCache = true;
    _groupChannelIndex = null;
    _idChannelIndex = null;
    _searchCache.clear();
  }

  // 统一JSON解析和异常处理
  static T _tryParseJson<T>(T Function() parser, String errorMessage) {
    try {
      return parser();
    } catch (e, stackTrace) {
      LogUtil.logError(errorMessage, e, stackTrace);
      return PlaylistModel() as T;
    }
  }
}

// 单个频道数据模型
class PlayModel {
  PlayModel({
    this.id,
    this.logo,
    this.title,
    this.group,
    this.urls,
  });

  String? id;
  String? title;
  String? logo;
  String? group;
  List<String>? urls;

  // 从JSON解析频道数据
  factory PlayModel.fromJson(dynamic json) {
    return PlaylistModel._tryParseJson(() {
      if (json is Map && json.isEmpty) return PlayModel();
      if (json is Map) {
        List<String> urlsList = List<String>.from(json['urls'] ?? []);
        return PlayModel(
          id: json['id'] as String?,
          logo: json['logo'] as String?,
          title: json['title'] as String?,
          group: json['group'] as String?,
          urls: urlsList.isEmpty ? null : urlsList,
        );
      }
      return PlayModel();
    }, '[PlayModel] 解析JSON出错');
  }

  // 创建带可选参数的副本
  PlayModel copyWith({
    String? id,
    String? logo,
    String? title,
    String? group,
    List<String>? urls,
  }) {
    return PlayModel(
      id: id ?? this.id,
      logo: logo ?? this.logo,
      urls: urls ?? this.urls,
      title: title ?? this.title,
      group: group ?? this.group,
    );
  }

  // 转换为JSON数据
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['id'] = id;
    map['logo'] = logo;
    map['title'] = title;
    map['group'] = group;
    map['urls'] = urls;
    return map;
  }
}
