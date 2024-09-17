/// 表示一个播放列表模型类，包含了EPG（电子节目指南）URL和按分类和组分类的可播放频道列表。
class PlaylistModel {
  /// 构造函数，用于创建一个 [PlaylistModel] 实例。
  ///
  /// [epgUrl] 是一个可选的字符串，指向EPG数据源的URL。
  /// [playList] 是一个三层嵌套的Map，其中：
  /// - 第一层 `String` 键是分类（例如：“区域”或“语言”），如果没有提供，则默认为 "所有频道"。
  ///   - 示例：对于 M3U 中未指定分类信息的情况，使用 "所有频道" 作为默认分类。
  /// - 第二层 `String` 键是组的标题（例如："体育"，"新闻"），从 `group-title` 提取。
  /// - 第三层 `Map` 将频道名称（`String`）与对应的 [PlayModel] 实例关联。

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
    // 校验JSON中是否包含必要字段
    if (json['epgUrl'] == null || json['playList'] == null) {
      return PlaylistModel(
        epgUrl: json['epgUrl'] as String?,
        playList: {},
      );
    }

    // 获取EPG URL
    String? epgUrl = json['epgUrl'] as String?;

    // 获取播放列表数据
    Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>;

    // 初始化播放列表
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
    if (channel == null && categoryOrGroup is String) {
      // 两个参数，旧的两层结构调用，categoryOrGroup 是组，groupOrChannel 是频道
      String group = categoryOrGroup;
      String channelName = groupOrChannel;

      // 从默认分类 "所有频道" 查找
      if (playList.containsKey('所有频道')) {
        return playList['所有频道']?[group]?[channelName];
      }

      // 如果分类不存在，直接查找组和频道
      for (var categoryMap in playList.values) {
        if (categoryMap.containsKey(group)) {
          return categoryMap[group]?[channelName];
        }
      }
    } else if (channel != null && categoryOrGroup is String) {
      // 三个参数，categoryOrGroup 是分类，groupOrChannel 是组，channel 是频道名称
      String category = categoryOrGroup;
      String group = groupOrChannel;

      // 从三层结构查找
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
  /// 构造函数，用于创建一个 [PlayModel] 实例。
  PlayModel({
    this.id,
    this.logo,
    this.urls,
    this.title,
    this.group,
  });

  /// 频道的唯一标识符，通常对应 `tvg-id`。
  String? id;

  /// 频道的显示名称或标题，通常对应 `group-title`。
  String? title;

  /// 频道的Logo图像的URL，通常对应 `tvg-logo`。
  String? logo;

  /// 该频道所属的组或类别（例如："体育"，"新闻"）。
  String? group;

  /// 频道的可播放URL列表，可能包含多个URL以提供备用或不同质量的流媒体链接。
  List<String>? urls;

  /// 工厂构造函数，通过JSON对象创建一个 [PlayModel] 实例。
  factory PlayModel.fromJson(dynamic json) {
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
