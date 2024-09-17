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
  /// 在M3U文件中提取自 `#EXTM3U` 标签的 `x-tvg-url`。
  /// 示例：`x-tvg-url="https://live.fanmingming.com/e.xml"`
  String? epgUrl;

  /// 按分类、分组和频道的Map结构
  late Map<String, Map<String, Map<String, PlayModel>>> playList;

  /// 从远程播放列表数据创建 [PlaylistModel] 实例。
  /// 如果没有提供 `category`，将其设置为 "所有频道"。
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    // 校验JSON中是否包含必要字段
    if (!json.containsKey('epgUrl') || !json.containsKey('playList')) {
      throw ArgumentError('JSON must contain epgUrl and playList');
    }

    // 获取EPG URL，使用 null-safety 处理
    String? epgUrl = json['epgUrl'] as String?;

    // 获取播放列表数据，确保playListJson为Map类型
    Map<String, dynamic>? playListJson = json['playList'];

    // 初始化播放列表
    Map<String, Map<String, Map<String, PlayModel>>> playList = {};

    if (playListJson is Map) {
      for (var entry in playListJson.entries) {
        String categoryKey = (entry.key is String && entry.key.isNotEmpty) ? entry.key : '所有频道';
        var groupMap = entry.value;

        if (groupMap is Map) {
          Map<String, Map<String, PlayModel>> groupMapTransformed = {};
          for (var groupEntry in groupMap.entries) {
            var channelMap = groupEntry.value;

            if (channelMap is Map) {
              Map<String, PlayModel> channelMapTransformed = {};
              for (var channelEntry in channelMap.entries) {
                var channelName = channelEntry.key;
                var channelJson = channelEntry.value;

                if (channelName is String && channelJson is Map) {
                  channelMapTransformed[channelName] = PlayModel.fromJson(channelJson);
                }
              }
              groupMapTransformed[groupEntry.key] = channelMapTransformed;
            }
          }
          playList[categoryKey] = groupMapTransformed;
        }
      }
    }

    return PlaylistModel(
      epgUrl: epgUrl,
      playList: playList,
    );
  }

  /// 按标题或组名搜索频道
  List<PlayModel> searchChannels(String keyword) {
    List<PlayModel> results = [];
    for (var groupMap in playList.values) {
      for (var channelMap in groupMap.values) {
        for (var channel in channelMap.values) {
          if (channel.title != null && channel.title!.contains(keyword) ||
              channel.group != null && channel.group!.contains(keyword)) {
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
  /// 构造函数，用于创建一个 [PlayModel] 实例。
  ///
  /// 接受频道的各种属性作为可选参数，例如 [id]、[logo]、[urls]、[title] 和 [group]。
  PlayModel({
    this.id,
    this.logo,
    this.urls,
    this.title,
    this.group,
  });

  /// 频道的唯一标识符，通常对应 `tvg-id`。
  /// 在M3U文件中从 `tvg-id` 属性中提取。
  String? id;

  /// 频道的显示名称或标题，通常对应 `group-title`。
  /// 在M3U文件中从 `tvg-name` 属性中提取。
  String? title;

  /// 频道的Logo图像的URL，通常对应 `tvg-logo`。
  /// 在M3U文件中从 `tvg-logo` 属性中提取。
  String? logo;

  /// 该频道所属的组或类别（例如："体育"，"新闻"）。
  /// 在M3U文件中从 `group-title` 属性中提取。
  String? group;

  /// 频道的可播放URL列表，可能包含多个URL以提供备用或不同质量的流媒体链接。
  /// 从M3U文件中的URL行提取，可能有多个播放源。
  List<String>? urls;

  /// 工厂构造函数，通过JSON对象创建一个 [PlayModel] 实例。
  ///
  /// - [json]：包含频道属性的JSON数据的动态对象。
  factory PlayModel.fromJson(dynamic json) {
    // 确保必需字段存在且有效
    if (json['id'] == null || json['urls'] == null) {
      throw ArgumentError('JSON must contain id and urls');
    }

    // 验证 urls 是否为有效的非空字符串列表
    List<String> urlsList = List<String>.from(json['urls'] ?? []);
    if (urlsList.isEmpty || urlsList.any((url) => url.isEmpty)) {
      throw ArgumentError('urls must be a non-empty list of strings');
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
  ///
  /// 返回一个新的 [PlayModel] 对象，如果未提供新的值，则保留现有值。
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
  ///
  /// 返回一个 `Map<String, dynamic>`，表示 [PlayModel] 的各个属性。
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
