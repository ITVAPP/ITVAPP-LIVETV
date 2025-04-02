import 'dart:convert';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// [epgUrl] 是一个可选的字符串，指向EPG数据源的URL。
/// [playList] 是一个三层嵌套的Map，其中：
/// - 第一层 `String` 键是分类（例如：“区域”或“语言”）
///   - 示例：对于 M3U 中未指定分类信息的情况，使用默认分类。
///   - 从 M3U 文件的 `#EXTINF` 标签中，如果没有独立的分类标签，使用默认分类。
/// - 第二层 `String` 键是组的标题（例如："体育"，"新闻"），从 `group-title` 提取。
///   - 示例：`group-title="央视频道"`，提取 "央视频道" 作为第二层键。
/// - 第三层 `Map` 将频道名称（`String`）与对应的 [PlayModel] 实例关联。
///   - 示例：`CCTV-1 综合` 作为第三层键，值是 `PlayModel` 对象。
/// 
/// ### M3U 播放列表示例：
/// ```
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

/// 播放列表模型类，包含EPG URL和按分类及组组织的频道列表
class PlaylistModel {
  PlaylistModel({
    this.epgUrl,
    Map<String, dynamic>? playList,
  }) : playList = playList ?? {}, _cachedChannels = null; // 修改说明：初始化缓存

  /// EPG（电子节目指南）的URL，用于获取节目信息
  String? epgUrl;

  /// 存储播放列表，支持两层或三层结构
  Map<String, dynamic> playList;

  /// 修改说明：添加频道缓存
  List<PlayModel>? _cachedChannels;

  /// 从JSON数据创建实例，处理播放列表解析
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return _tryParseJson(() {
      LogUtil.i('fromJson处理传入的数据：${json.keys}'); // 记录键，避免泄露完整数据
      String? epgUrl = json['epgUrl'] as String?;
      Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>? ?? {};
      Map<String, dynamic> playList = playListJson.isNotEmpty ? _parsePlayList(playListJson) : {};
      return PlaylistModel(epgUrl: epgUrl, playList: playList);
    }, '解析 PlaylistModel 时出错');
  }

  /// 从字符串解析实例，调用fromJson处理
  static PlaylistModel fromString(String data) {
    return _tryParseJson(() {
      LogUtil.i('fromString处理传入的数据长度：${data.length}'); // 记录长度而非完整数据
      final Map<String, dynamic> jsonData = jsonDecode(data);
      return PlaylistModel.fromJson(jsonData);
    }, '从字符串解析 PlaylistModel 时出错');
  }

  /// 判断播放列表是否为三层结构
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

  /// 转换为JSON字符串，处理空ID频道并添加异常捕获
  @override
  String toString() {
    try {
      if (playList != null) {
        playList.forEach((category, groups) {
          if (groups is Map<String, dynamic>) {
            groups.forEach((groupTitle, channels) {
              if (channels is Map<String, dynamic>) {
                channels.forEach((channelName, channel) {
                  if (channel is PlayModel) {
                    if (channel.id == null || channel.id!.isEmpty) {
                      LogUtil.i('发现无ID频道: $channelName，使用名称作为ID');
                      channel.id = channelName;
                    }
                  }
                });
              }
            });
          }
        });
      }
      return jsonEncode({'epgUrl': epgUrl, 'playList': playList});
    } catch (e, stackTrace) {
      LogUtil.logError('转换 PlaylistModel 到字符串时出错', e, stackTrace);
      return '{"epgUrl": null, "playList": {}}'; // 返回安全默认值
    }
  }

  /// 根据嵌套深度解析播放列表，支持两层或三层结构
  static Map<String, dynamic> _parsePlayList(Map<String, dynamic> json) {
    try {
      LogUtil.i('parsePlayList处理传入的键：${json.keys}');
      if (json.isEmpty) {
        LogUtil.i('空的播放列表结构，返回

默认三层结构');
        return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
      }
      Map<String, dynamic> sanitizedJson = {};
      json.forEach((key, value) {
        sanitizedJson[key.toString()] = value;
      });
      if (_isThreeLayerStructure(sanitizedJson)) {
        LogUtil.i('处理三层结构的播放列表');
        return _parseThreeLayer(sanitizedJson);
      }
      LogUtil.i('处理两层结构的播放列表，转换为三层');
      return _parseThreeLayer({Config.allChannelsKey: _parseTwoLayer(sanitizedJson)});
    } catch (e, stackTrace) {
      LogUtil.logError('解析播放列表结构时出错', e, stackTrace);
      return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
    }
  }

  /// 获取指定频道，优化为类型安全且减少遍历
  PlayModel? getChannel(dynamic categoryOrGroup, String groupOrChannel, [String? channel]) {
    if (channel == null && categoryOrGroup is String) {
      String group = categoryOrGroup;
      String channelName = groupOrChannel;
      // 优先检查默认分类
      if (playList.containsKey(Config.allChannelsKey)) {
        var defaultCategory = playList[Config.allChannelsKey];
        if (defaultCategory is Map<String, Map<String, PlayModel>> &&
            defaultCategory.containsKey(group)) {
          return defaultCategory[group]?[channelName];
        }
      }
      // 单次查找其他分类
      var categoryMap = playList.values.firstWhere(
        (map) => map is Map<String, Map<String, PlayModel>> && map.containsKey(group),
        orElse: () => null,
      );
      if (categoryMap != null) {
        return (categoryMap as Map<String, Map<String, PlayModel>>)[group]?[channelName];
      }
    } else if (channel != null && categoryOrGroup is String) {
      String category = categoryOrGroup;
      String group = groupOrChannel;
      if (playList[category] is Map<String, Map<String, PlayModel>> &&
          playList.containsKey(category)) {
        return (playList[category] as Map<String, Map<String, PlayModel>>)[group]?[channel];
      }
    }
    return null;
  }

  /// 解析三层结构播放列表，返回分类-组-频道映射
  static Map<String, Map<String, Map<String, PlayModel>>> _parseThreeLayer(Map<String, dynamic> json) {
    Map<String, Map<String, Map<String, PlayModel>>> result = {};
    try {
      for (var entry in json.entries) {
        String category = entry.key.isNotEmpty ? entry.key : Config.allChannelsKey;
        var groupMapJson = entry.value;
        if (groupMapJson is! Map) {
          LogUtil.i('跳过无效组映射: $category -> $groupMapJson');
          continue;
        }
        result[category] = _handleEmptyMap<Map<String, Map<String, PlayModel>>>(groupMapJson, (groupMap) {
          Map<String, Map<String, PlayModel>> groupMapResult = {};
          for (var groupEntry in groupMap.entries) {
            String groupTitle = groupEntry.key.toString();
            var channelMapJson = groupEntry.value;
            if (channelMapJson is! Map) {
              LogUtil.i('跳过无效频道映射: $groupTitle -> $channelMapJson');
              continue;
            }
            groupMapResult[groupTitle] = _handleEmptyMap<Map<String, PlayModel>>(channelMapJson, (channelMap) {
              Map<String, PlayModel> channels = {};
              for (var channelEntry in channelMap.entries) {
                String channelName = channelEntry.key.toString();
                var channelData = channelEntry.value;
                channels[channelName] = channelData is Map<String, dynamic>
                    ? PlayModel.fromJson(channelData)
                    : PlayModel();
              }
              return channels;
            });
          }
          return groupMapResult;
        });
      }
    } catch (e, stackTrace) {
      LogUtil.logError('解析三层播放列表时出错', e, stackTrace);
    }
    return result.isEmpty ? {Config.allChannelsKey: <String, Map<String, PlayModel>>{}} : result;
  }

  /// 解析两层结构播放列表，返回组-频道映射
  static Map<String, Map<String, PlayModel>> _parseTwoLayer(Map<String, dynamic> json) {
    Map<String, Map<String, PlayModel>> result = {};
    try {
      json.forEach((groupTitle, channelMapJson) {
        String sanitizedGroupTitle = groupTitle.toString();
        if (channelMapJson is! Map) {
          LogUtil.i('跳过无效频道映射: $sanitizedGroupTitle -> $channelMapJson');
          return;
        }
        result[sanitizedGroupTitle] = _handleEmptyMap<Map<String, PlayModel>>(channelMapJson, (channelMap) {
          Map<String, PlayModel> channels = {};
          channelMap.forEach((channelName, channelData) {
            String sanitizedChannelName = channelName.toString();
            channels[sanitizedChannelName] = channelData is Map<String, dynamic>
                ? PlayModel.fromJson(channelData)
                : PlayModel();
          });
          return channels;
        });
      });
    } catch (e, stackTrace) {
      LogUtil.logError('解析两层播放列表时出错', e, stackTrace);
    }
    return result.isEmpty ? <String, Map<String, PlayModel>>{} : result;
  }

  /// 搜索匹配关键字的频道，使用缓存提升性能
  List<PlayModel> searchChannels(String keyword) {
    if (_cachedChannels == null) {
      _cachedChannels = [];
      for (var groupMap in playList.values) {
        if (groupMap is Map<String, Map<String, PlayModel>>) {
          for (var channelMap in groupMap.values) {
            _cachedChannels!.addAll(channelMap.values);
          }
        }
      }
    }
    return _cachedChannels!.where((channel) =>
        (channel.title?.contains(keyword) ?? false) ||
        (channel.group?.contains(keyword) ?? false)).toList();
  }

  /// 统一处理空Map逻辑，返回指定类型结果
  static T _handleEmptyMap<T>(dynamic input, T Function(Map<String, dynamic>) parser) {
    if (input is! Map || input.isEmpty) {
      if (T == Map<String, Map<String, PlayModel>>) {
        return <String, Map<String, PlayModel>>{} as T;
      } else if (T == Map<String, PlayModel>) {
        return <String, PlayModel>{} as T;
      }
      throw Exception('Unsupported type for _handleEmptyMap: $T');
    }
    return parser(input as Map<String, dynamic>);
  }

  /// 统一JSON解析和异常处理，返回类型安全的默认值
  static T _tryParseJson<T>(T Function() parser, String errorMessage) {
    try {
      return parser();
    } catch (e, stackTrace) {
      LogUtil.logError(errorMessage, e, stackTrace);
      return PlaylistModel() as T;
    }
  }
}

/// 单个可播放频道的数据模型
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

  /// 从JSON数据创建实例，支持空数据处理
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
    }, '解析 PlayModel JSON 时出错');
  }

  /// 创建带可选参数的副本实例
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

  /// 转换为JSON格式数据
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
