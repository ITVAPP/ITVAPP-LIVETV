import 'dart:convert';
import 'package:itvapp_live_tv/util/log_util.dart';
import '../config.dart';

  /// 构造函数，用于创建一个 [PlaylistModel] 实例。
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

/// 表示一个播放列表模型类，包含了EPG（电子节目指南）URL和按分类和组分类的可播放频道列表。
class PlaylistModel {

  PlaylistModel({
    this.epgUrl,
    Map<String, dynamic>? playList,
  }) : playList = playList ?? {};

  /// 节目（EPG）的URL，用于获取节目相关信息。
  String? epgUrl;

  /// 存储播放列表的数据结构，支持两层和三层结构
  Map<String, dynamic> playList;

  /// 从远程播放列表数据创建 [PlaylistModel] 实例。
  /// [json] 包含播放列表信息的 JSON 格式数据。
  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    try {
      LogUtil.i('fromJson处理传入的数据： ${json}');
      String? epgUrl = json['epgUrl'] as String?;
      Map<String, dynamic> playListJson = json['playList'] as Map<String, dynamic>? ?? {};

      // 使用 _parsePlayList 方法处理结构
      Map<String, dynamic> playList = playListJson != null ? _parsePlayList(playListJson) : {};

      return PlaylistModel(epgUrl: epgUrl, playList: playList);
    } catch (e, stackTrace) {
      LogUtil.logError('解析 PlaylistModel 时出错', e, stackTrace);
      return PlaylistModel(); // 返回一个空的 PlaylistModel
    }
  }

  /// 从字符串解析 [PlaylistModel] 实例
static PlaylistModel fromString(String data) {
  try {
    LogUtil.i('fromString处理传入的数据： ${data}');
    final Map<String, dynamic> jsonData = jsonDecode(data);
    
    // 这里是本地缓存读取，强制按三层处理
    if (jsonData['playList'] != null) {
      // 如果是两层结构，转换成三层
      Map<String, dynamic> playList = jsonData['playList'];
      if (!_isThreeLayerStructure(playList)) {
        // 包装成三层结构
        playList = {
          Config.allChannelsKey: playList
        };
        jsonData['playList'] = playList;
      }
    }
    
    return PlaylistModel.fromJson(jsonData);
  } catch (e, stackTrace) {
    LogUtil.logError('从字符串解析 PlaylistModel 时出错', e, stackTrace);
    return PlaylistModel();
  }
}

// 添加辅助方法判断结构
static bool _isThreeLayerStructure(Map<String, dynamic> json) {
 if (json.isEmpty) return false;
 
 // 遍历所有值，检查是否有任何一个值符合三层结构 
 for (var firstValue in json.values) {
   if (firstValue is! Map) continue;
   // 如果是空的 Map，认为是有效的层级
   if (firstValue.isEmpty) continue; 
   
   // 检查第二层
   for (var secondValue in firstValue.values) {
     if (secondValue is Map) return true;
   }
 }
 return false;
}

  /// 将 [PlaylistModel] 实例转换为 JSON 字符串格式
@override
String toString() {
  if (playList != null) {
    playList.forEach((category, groups) {
      if (groups is Map<String, dynamic>) {
        groups.forEach((groupTitle, channels) {
          if (channels is Map<String, dynamic>) {
            channels.forEach((channelName, channel) {
              if (channel is PlayModel) {
                // 如果 ID 为空，使用频道名称作为 ID
                if (channel.id == null || channel.id!.isEmpty) {
                  LogUtil.i('发现无 ID 频道: $channelName，使用频道名称作为 ID');
                  channel.id = channelName;
                }
              }
            });
          }
        });
      }
    });
  }
  
  return jsonEncode({
    'epgUrl': epgUrl,
    'playList': playList,
  });
}

  /// 自动判断并解析播放列表结构（两层或三层）
/// 根据播放列表的嵌套深度（两层或三层）选择相应的解析方式。
static Map<String, dynamic> _parsePlayList(Map<String, dynamic> json) {
 try {
   LogUtil.i('parsePlayList处理传入的数据： ${json}');

   // 如果json为空,返回默认三层结构
   if (json.isEmpty) {
     LogUtil.i('空的播放列表结构，返回默认三层结构');
     return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
   }

   // 检测是三层结构还是两层结构
   bool isThreeLayer = json.values.isNotEmpty && // 确保有值可检查
       json.values.first is Map<String, dynamic> &&
       (json.values.first as Map<String, dynamic>).isNotEmpty && // 检查第一层嵌套不为空
       (json.values.first as Map<String, dynamic>).values.isNotEmpty && // 确保有第二层值
       (json.values.first as Map<String, dynamic>).values.first is Map<String, dynamic>; // 确保是Map而不是PlayModel

   if (isThreeLayer) {
     LogUtil.i('处理三层结构的播放列表');
     return _parseThreeLayer(json);
   }

   // 两层结构转换为三层
   LogUtil.i('处理两层结构的播放列表，转换为三层');
   return _parseThreeLayer({
     Config.allChannelsKey: _parseTwoLayer(json)
   });

 } catch (e, stackTrace) {
   LogUtil.logError('解析播放列表结构时出错', e, stackTrace);
   return {Config.allChannelsKey: <String, Map<String, PlayModel>>{}};
 }
}

  /// 自动判断使用两层还是三层结构的 getChannel 方法
  /// [categoryOrGroup] 可以是分类（String）或组（String）。
  /// [groupOrChannel] 如果 [categoryOrGroup] 是分类，则表示组名；如果是组，则表示频道名。
  /// [channel] 仅在使用三层结构时提供，用于指定频道名称。
  PlayModel? getChannel(dynamic categoryOrGroup, String groupOrChannel, [String? channel]) {
    if (channel == null && categoryOrGroup is String) {
      // 两个参数，处理两层结构
      String group = categoryOrGroup;
      String channelName = groupOrChannel;

      // 优化：先检查默认分类，减少不必要的遍历
      if (playList.containsKey(Config.allChannelsKey)) {
        var defaultCategory = playList[Config.allChannelsKey];
        if (defaultCategory is Map<String, Map<String, PlayModel>>) {
          var result = defaultCategory[group]?[channelName];
          if (result != null) return result;
        }
      }

      // 如果默认分类未找到，遍历其他分类
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
    return null;
  }

  /// 解析三层结构的播放列表
  /// - 第一层为分类
  /// - 第二层为组
  /// - 第三层为频道
static Map<String, Map<String, Map<String, PlayModel>>> _parseThreeLayer(
   Map<String, dynamic> json) {
 Map<String, Map<String, Map<String, PlayModel>>> result = {};
 try {
   for (var entry in json.entries) {
     String category = entry.key.isNotEmpty ? entry.key : Config.allChannelsKey;
     var groupMapJson = entry.value;

     // 如果分类是空的，保存为标准的空分类结构
     if (groupMapJson is! Map || (groupMapJson as Map).isEmpty) {
       result[category] = <String, Map<String, PlayModel>>{};
       continue;  // 使用 continue 而不是 return
     }
     
     if (groupMapJson is Map<String, dynamic>) {
       Map<String, Map<String, PlayModel>> groupMap = {};
       for (var groupEntry in groupMapJson.entries) {
         var groupTitle = groupEntry.key;
         var channelMapJson = groupEntry.value;

         // 如果组是空的，保存为标准的空组结构
         if (channelMapJson is! Map || (channelMapJson as Map).isEmpty) {
           groupMap[groupTitle] = <String, PlayModel>{};
           continue;  // 使用 continue 而不是 return
         }

         if (channelMapJson is Map<String, dynamic>) {
           Map<String, PlayModel> channelMap = {};
           channelMapJson.forEach((channelName, channelData) {
             if (channelData is Map && channelData.isEmpty) {
               return; 
             }
             PlayModel playModel = PlayModel.fromJson(channelData);
             if (playModel.isValid) {
               channelMap[channelName] = playModel;
             }
           });
           groupMap[groupTitle] = channelMap;
         }
       }
       result[category] = groupMap;
     }
   }
 } catch (e, stackTrace) {
   LogUtil.logError('解析三层播放列表时出错', e, stackTrace);
 }
 return result;
}

  /// 解析两层结构的播放列表
  /// - 第一层为组
  /// - 第二层为频道
  static Map<String, Map<String, PlayModel>> _parseTwoLayer(
      Map<String, dynamic> json) {
    Map<String, Map<String, PlayModel>> result = {};
    try {
      json.forEach((groupTitle, channelMapJson) {
        if (channelMapJson is Map<String, dynamic>) {
          Map<String, PlayModel> channelMap = {};
          channelMapJson.forEach((channelName, channelData) {
            PlayModel playModel = PlayModel.fromJson(channelData);
            if (playModel.isValid) { // 检查 PlayModel 是否有效
              channelMap[channelName] = playModel;
            }
          });
          if (channelMap.isNotEmpty) {
            result[groupTitle] = channelMap;
          }
        }
      });
    } catch (e, stackTrace) {
      LogUtil.logError('解析两层播放列表时出错', e, stackTrace);
    }
    return result;
  }

  /// 按标题或组名搜索频道
  /// [keyword] 要搜索的关键词。
  /// 返回包含匹配的 [PlayModel] 实例的列表。
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
    this.title,
    this.group,
    this.urls,
  });

  String? id; // 频道的唯一标识符
  String? title; // 频道的名称
  String? logo; // 频道的Logo URL
  String? group; // 频道所属的组
  List<String>? urls; // 频道的可播放地址列表

  /// 从 JSON 数据创建 [PlayModel] 实例
  factory PlayModel.fromJson(dynamic json) {
    try {
      // 确保 id 存在并且非空，否则返回一个无效的 PlayModel 实例
      if (json['id'] == null || (json['id'] as String).isEmpty) {
        LogUtil.i('PlayModel JSON 缺少必需的 ID 字段');
        return PlayModel.invalid(); // 返回无效 PlayModel
      }

      List<String> urlsList = List<String>.from(json['urls'] ?? []);

      return PlayModel(
        id: json['id'] as String?,
        logo: json['logo'] as String?,
        title: json['title'] as String?,
        group: json['group'] as String?,
        urls: urlsList.isEmpty ? null : urlsList, // 保留 urls 为空的情况
      );
    } catch (e, stackTrace) {
      LogUtil.logError('解析 PlayModel JSON 时出错', e, stackTrace);
      return PlayModel.invalid(); // 解析失败时返回无效 PlayModel
    }
  }

  /// 返回一个无效的 PlayModel 实例
  factory PlayModel.invalid() {
    return PlayModel(
      id: 'invalid', // 设定特殊的 ID 标识无效
      title: 'Invalid Channel',
      logo: '',
      group: '',
      urls: [],
    );
  }

  /// 检查 PlayModel 是否有效
  bool get isValid => id != 'invalid';

  /// 创建一个新的 [PlayModel] 实例，保留当前实例的属性，并用新值覆盖
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

  /// 将 [PlayModel] 实例转换为 JSON 格式
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
