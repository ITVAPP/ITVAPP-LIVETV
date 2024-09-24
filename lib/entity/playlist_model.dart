import 'dart:convert';

/// 表示一个播放列表模型类，包含了EPG（电子节目指南）URL和按分类和组分类的可播放频道列表。
class PlaylistModel {
  /// 构造函数，用于创建一个 [PlaylistModel] 实例。
  /// [epgUrl] 是一个可选的字符串，指向EPG数据源的URL。
  /// [playList] 是一个三层嵌套的Map，其中：
  /// - 第一层 `String` 键是分类（例如：“区域”或“语言”），如果没有提供，则默认为 "所有频道"。
  ///   - 示例：对于 M3U 中未指定分类信息的情况，使用 "所有频道" 作为默认分类。
  ///   - 从 M3U 文件的 `#EXTINF` 标签中，如果没有独立的分类标签，使用 "所有频道" 作为分类。
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

  PlaylistModel({
    this.epgUrl,
    Map<String, dynamic>? playList,
  }) : playList = playList ?? {};

  /// 电子节目指南（EPG）的URL，用于获取节目相关信息。
  String? epgUrl;

  /// 存储播放列表的数据结构，支持两层和三层结构
  Map<String, dynamic> playList;

  /// 从远程播放列表数据创建 [PlaylistModel] 实例。
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    if (json['epgUrl'] == null || json['playList'] == null) {
      return PlaylistModel(epgUrl: json['epgUrl'], playList: {});
    }

    String? epgUrl = json['epgUrl'] as String?;
    Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>;

    // 判断数据结构，并解析
    Map<String, dynamic> playList = _parsePlayList(playListJson);

    return PlaylistModel(epgUrl: epgUrl, playList: playList);
  }

  /// 从字符串解析 [PlaylistModel] 实例（通常从缓存中读取）
  static PlaylistModel fromString(String data) {
    final Map<String, dynamic> jsonData = jsonDecode(data);

    // 确保 JSON 数据中的 playList 正确解析为嵌套的结构
    if (jsonData['playList'] != null) {
      Map<String, Map<String, Map<String, PlayModel>>> playList = 
        (jsonData['playList'] as Map<String, dynamic>).map((categoryKey, groupMap) {
          return MapEntry(
            categoryKey,
            (groupMap as Map<String, dynamic>).map((groupTitle, channelMap) {
              return MapEntry(
                groupTitle,
                (channelMap as Map<String, dynamic>).map((channelName, channelData) {
                  return MapEntry(channelName, PlayModel.fromJson(channelData));
                }),
              );
            }),
          );
        });

      return PlaylistModel(
        epgUrl: jsonData['epgUrl'],
        playList: playList,
      );
    }

    return PlaylistModel(epgUrl: jsonData['epgUrl'], playList: {});
  }

  /// 将 [PlaylistModel] 实例转换为字符串（通常用于存储到缓存中）
  @override
  String toString() {
    return jsonEncode({
      'epgUrl': epgUrl,
      'playList': playList,
    });
  }

  /// 自动判断并解析播放列表结构（两层或三层）
  static Map<String, dynamic> _parsePlayList(Map<String, dynamic> json) {
    // 检测是三层结构还是两层结构
    bool isThreeLayer = json.values.first is Map<String, dynamic> &&
        (json.values.first as Map<String, dynamic>).values.first is Map<String, dynamic>;

    // 如果是三层结构，解析为三层；否则解析为两层
    return isThreeLayer ? _parseThreeLayer(json) : _parseTwoLayer(json);
  }

  /// 解析三层结构的播放列表
  static Map<String, Map<String, Map<String, PlayModel>>> _parseThreeLayer(
      Map<String, dynamic> json) {
    Map<String, Map<String, Map<String, PlayModel>>> result = {};
    json.forEach((categoryKey, groupMapJson) {
      String category = categoryKey.isNotEmpty ? categoryKey : '所有频道';

      if (groupMapJson is Map<String, dynamic>) {
        Map<String, Map<String, PlayModel>> groupMap = {};
        groupMapJson.forEach((groupTitle, channelMapJson) {
          if (channelMapJson is Map<String, dynamic>) {
            Map<String, PlayModel> channelMap = {};
            channelMapJson.forEach((channelName, channelData) {
              PlayModel? playModel = PlayModel.fromJson(channelData);
              if (playModel != null) {
                channelMap[channelName] = playModel;
              }
            });
            groupMap[groupTitle] = channelMap;
          }
        });
        result[category] = groupMap;
      }
    });
    return result;
  }

  /// 解析两层结构的播放列表
  static Map<String, Map<String, PlayModel>> _parseTwoLayer(
      Map<String, dynamic> json) {
    Map<String, Map<String, PlayModel>> result = {};
    json.forEach((groupTitle, channelMapJson) {
      if (channelMapJson is Map<String, dynamic>) {
        Map<String, PlayModel> channelMap = {};
        channelMapJson.forEach((channelName, channelData) {
          PlayModel? playModel = PlayModel.fromJson(channelData);
          if (playModel != null) {
            channelMap[channelName] = playModel;
          }
        });
        result[groupTitle] = channelMap;
      }
    });
    return result;
  }

  /// 自动判断使用两层还是三层结构的 getChannel 方法
  PlayModel? getChannel(dynamic categoryOrGroup, String groupOrChannel,
      [String? channel]) {
    if (channel == null && categoryOrGroup is String) {
      // 两个参数，处理两层结构
      String group = categoryOrGroup;
      String channelName = groupOrChannel;

      // 尝试从 "所有频道" 中查找
      if (playList.containsKey('所有频道')) {
        return (playList['所有频道'] as Map<String, Map<String, PlayModel>>)[group]?[channelName];
      }

      // 如果分类不存在，直接查找组和频道
      for (var categoryMap in playList.values) {
        if (categoryMap is Map<String, Map<String, PlayModel>> &&
            categoryMap.containsKey(group)) {
          return categoryMap[group]?[channelName];
        }
      }
    } else if (channel != null && categoryOrGroup is String) {
      // 三个参数，处理三层结构
      String category = categoryOrGroup;
      String group = groupOrChannel;

      // 从三层结构查找
      if (playList[category] is Map<String, Map<String, PlayModel>>) {
        return (playList[category] as Map<String, Map<String, PlayModel>>)[group]?[channel];
      }
    }

    // 如果找不到频道，返回 null
    return null;
  }

  /// 按标题或组名搜索频道
  List<PlayModel> searchChannels(String keyword) {
    List<PlayModel> results = [];
    for (var groupMap in playList.values) {
      if (groupMap is Map<String, Map<String, PlayModel>>) {
        for (var channelMap in groupMap.values) {
          for (var channel in channelMap.values) {
            if ((channel.title?.contains(keyword) ?? false) ||
                (channel.group?.contains(keyword) ?? false)) {
              results.add(channel);
            }
          }
        }
      }
    }
    return results;
  }
}

/// 表示单个可播放频道的模型类。
class PlayModel {
  PlayModel({
    this.id,
    this.logo,
    this.urls,
    this.title,
    this.group,
  });

  String? id;
  String? title;
  String? logo;
  String? group;
  List<String>? urls;

  factory PlayModel.fromJson(dynamic json) {
    if (json['id'] == null || json['urls'] == null) {
      return PlayModel(); // 返回默认实例而不是null
    }

    List<String> urlsList = List<String>.from(json['urls'] ?? []);
    if (urlsList.isEmpty || urlsList.any((url) => url.isEmpty)) {
      return PlayModel(); // 返回默认实例而不是null
    }

    return PlayModel(
      id: json['id'] as String?,
      logo: json['logo'] as String?,
      title: json['title'] as String?,
      group: json['group'] as String?,
      urls: urlsList,
    );
  }

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

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['id'] = id;
    map['logo'] = logo;
    map['urls'] = urls;
    map['title'] = title;
    map['group'] = group;
    return map;
  }
}
