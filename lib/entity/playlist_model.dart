/// 表示一个播放列表模型类，包含了EPG（电子节目指南）URL和按分类和组分类的可播放频道列表。
class PlaylistModel {
  /// 构造函数，用于创建一个 [PlaylistModel] 实例。
  ///
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
  /// # 央视频道分类
  /// #EXTINF:-1 tvg-id="CCTV1" tvg-name="CCTV-1 综合" tvg-logo=" http://example.com/CCTV1.png" group-title="央视频道",CCTV-1 综合
  /// http://example.com/cctv1.m3u8
  ///
  /// #EXTINF:-1 tvg-id="CCTV2" tvg-name="CCTV-2 财经" tvg-logo=" http://example.com/CCTV2.png" group-title="央视频道",CCTV-2 财经
  /// http://example.com/cctv2.m3u8
  ///
  /// # 娱乐频道分类
  /// #EXTINF:-1 tvg-id="HunanTV" tvg-name="湖南卫视" tvg-logo=" http://example.com/HunanTV.png" group-title="娱乐频道",湖南卫视
  /// http://example.com/hunantv.m3u8
  ///
  /// # 体育频道分类
  /// #EXTINF:-1 tvg-id="CCTV5" tvg-name="CCTV-5 体育" tvg-logo=" http://example.com/CCTV5.png" group-title="体育频道",CCTV-5 体育
  /// http://example.com/cctv5.m3u8
  /// ```

  PlaylistModel({
    this.epgUrl,
    Map<String, Map<String, Map<String, PlayModel>>>? playList,
  }) : playList = playList ?? {};

  /// 电子节目指南（EPG）的URL，用于获取节目相关信息。
  String? epgUrl;

  /// 按分类、分组和频道的Map结构
  late Map<String, Map<String, Map<String, PlayModel>>> playList;

  /// 从远程播放列表数据创建 [PlaylistModel] 实例。
  /// 如果没有提供 `category`，将其设置为 "所有频道"。
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    if (json['epgUrl'] == null || json['playList'] == null) {
      return PlaylistModel(
        epgUrl: json['epgUrl'] as String?,
        playList: {},
      );
    }

    String? epgUrl = json['epgUrl'] as String?;
    Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>;
    Map<String, Map<String, Map<String, PlayModel>>> playList = {};

    playListJson.forEach((categoryKey, groupMapJson) {
      String category = categoryKey.isNotEmpty ? categoryKey : '所有频道';

      if (groupMapJson is Map<String, dynamic>) {
        Map<String, Map<String, PlayModel>> groupMap = {};

        groupMapJson.forEach((groupTitle, channelMapJson) {
          if (channelMapJson is Map<String, dynamic>) {
            Map<String, PlayModel> channelMap = {};

            channelMapJson.forEach((channelName, channelData) {
              if (channelData is Map<String, dynamic>) {
                PlayModel? playModel = PlayModel.fromJson(channelData);
                if (playModel != null) {
                  channelMap[channelName] = playModel;
                }
              }
            });

            groupMap[groupTitle] = channelMap;
          }
        });

        playList[category] = groupMap;
      }
    });

    return PlaylistModel(
      epgUrl: epgUrl,
      playList: playList,
    );
  }

  /// 自动判断使用两层还是三层结构的 getChannel 方法
  PlayModel? getChannel(dynamic categoryOrGroup, String groupOrChannel, [String? channel]) {
    if (channel == null) {
      // 两个参数：如果 `categoryOrGroup` 是组名并且不存在分类信息，按二层结构处理
      String group = categoryOrGroup as String;
      String channelName = groupOrChannel;

      // 如果是二层结构，直接从 "所有频道" 中查找
      if (playList.containsKey('所有频道')) {
        return playList['所有频道']?[group]?[channelName];
      }

      // 如果没有找到，遍历所有分类下的组名进行查找
      for (var categoryMap in playList.values) {
        if (categoryMap.containsKey(group)) {
          return categoryMap[group]?[channelName];
        }
      }
    } else {
      // 三个参数：按三层结构查找
      String category = categoryOrGroup as String;
      String group = groupOrChannel;

      return playList[category]?[group]?[channel];
    }

    // 如果找不到频道，返回 null
    return null;
  }

  /// 按标题或组名搜索频道
  List<PlayModel> searchChannels(String keyword) {
    List<PlayModel> results = [];
    for (var groupMap in playList.values) {
      for (var channelMap in groupMap.values) {
        for (var channel in channelMap.values) {
          if ((channel.title?.contains(keyword) ?? false) ||
              (channel.group?.contains(keyword) ?? false)) {
            results.add(channel);
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

  /// 通过JSON对象创建一个 [PlayModel] 实例。
  static PlayModel? fromJson(dynamic json) {
    // 如果 'id' 或 'urls' 缺失，直接跳过创建 PlayModel
    if (json['id'] == null || json['urls'] == null) {
      return null;
    }

    // 验证 urls 是否为有效的非空字符串列表
    List<String> urlsList = List<String>.from(json['urls'] ?? []);
    if (urlsList.isEmpty || urlsList.any((url) => url.isEmpty)) {
      return null; // 跳过无效的 URL
    }

    return PlayModel(
      id: json['id'] as String?,
      logo: json['logo'] as String?,
      title: json['title'] as String?,
      group: json['group'] as String?,
      urls: urlsList,
    );
  }

  /// 创建当前 [PlayModel] 实例的副本，可以选择性地覆盖特定字段。
  PlayModel copyWith({
    String? id,
    String? logo,
    String? title,
    String? group,
    List<String>? urls,
  }) =>
      PlayModel(
        id: id ?? this.id,
        logo: logo ?? this.logo,
        urls: urls ?? this.urls,
        title: title ?? this.title,
        group: group ?? this.group,
      );

  /// 将 [PlayModel] 实例转换为可兼容JSON格式的 `Map` 对象。
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
