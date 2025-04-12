import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// channel_name : "CCTV1"
/// date : ""
/// epg_data : []
class EpgUtil {
  EpgUtil._(); // 私有构造函数，防止实例化

  static final Map<String, EpgModel> epgCacheMap = <String, EpgModel>{}; // 缓存 EPG 数据
  static Iterable<XmlElement>? _programmes; // 存储解析后的 XML 节目数据

  // 获取 EPG 数据，支持缓存、XML 和网络请求
  static Future<EpgModel?> getEpg(PlayModel? model, {CancelToken? cancelToken}) async {
    if (model == null) return null; // 检查输入模型是否为空

    String channelKey = '';
    String channel = '';
    String date = '';
    final isHasXml = _programmes != null && _programmes!.isNotEmpty; // 检查 XML 数据是否可用

    if (model.id != null && model.id!.isNotEmpty && isHasXml) {
      channelKey = model.id!; // 三层结构使用频道 ID 作为键
    } else {
      if (model.title == null) return null; // 检查标题是否为空
      channel = model.title!.replaceAll(' ', '').replaceAll('-', ''); // 清理频道名称
      date = DateUtil.formatDate(DateTime.now(), format: "yyMMdd"); // 获取当前日期
      channelKey = "$date-$channel"; // 两层结构使用日期和频道名组合键
    }

    if (epgCacheMap.containsKey(channelKey)) {
      return epgCacheMap[channelKey]!; // 返回缓存中的 EPG 数据
    }

    if (isHasXml) {
      EpgModel epgModel = EpgModel(channelName: model.title ?? '未知频道', epgData: []); // 初始化 EPG 模型
      for (var programme in _programmes!) {
        final channel = programme.getAttribute('channel');
        if (channel == model.id) {
          final start = programme.getAttribute('start')!; // 获取节目开始时间
          final dateStart = DateUtil.formatDate(DateUtil.parseCustomDateTimeString(start), format: "HH:mm");
          final stop = programme.getAttribute('stop')!; // 获取节目结束时间
          final dateEnd = DateUtil.formatDate(DateUtil.parseCustomDateTimeString(stop), format: "HH:mm");
          final title = programme.findAllElements('title').first.innerText; // 获取节目标题
          epgModel.epgData!.add(EpgData(title: title, start: dateStart, end: dateEnd)); // 添加节目数据
        }
      }
      if (epgModel.epgData!.isEmpty) return null; // 无数据时返回 null
      epgCacheMap[channelKey] = epgModel; // 缓存 EPG 数据
      return epgModel;
    }

    if (cancelToken?.isCancelled ?? false) return null; // 请求取消时返回 null
    
    final epgRes = await HttpUtil().getRequest(
      '${Config.epgBaseUrl}?ch=$channel&date=$date', // 使用 Config 中的 EPG 地址
      cancelToken: cancelToken, // 支持取消网络请求
    );
    if (epgRes != null && epgRes['channel_name'] == channel) {
      final epg = EpgModel.fromJson(epgRes); // 解析 JSON 数据
      epgCacheMap[channelKey] = epg; // 缓存结果
      return epg;
    }
    return null; // 无有效数据时返回 null
  }

  // 加载 EPG XML 文件，支持重试机制
  static Future<void> loadEPGXML(String url) async {
    int index = 0;
    const int maxRetries = 3; // 最大重试次数
    final uStr = url.replaceAll('/h', ',h');
    final urlLink = uStr.split(','); // 分割 URL 列表
    XmlDocument? tempXmlDocument;

    while (tempXmlDocument == null && index < urlLink.length && index < maxRetries) {
      final res = await HttpUtil().getRequest(urlLink[index]); // 请求 XML 数据
      if (res != null) {
        try {
          tempXmlDocument = XmlDocument.parse(res.toString()); // 解析 XML
        } catch (e) {
          LogUtil.e('解析 XML 失败: $e');
          index += 1; // 解析失败时尝试下一个 URL
        }
      } else {
        index += 1; // 请求失败时尝试下一个 URL
      }
    }
    _programmes = tempXmlDocument?.findAllElements('programme'); // 存储节目数据
  }

  // 重置 EPG XML 数据
  static void resetEPGXML() {
    _programmes = null; // 清空节目数据
  }
}

// EPG 数据模型
class EpgModel {
  EpgModel({this.channelName, this.date, this.epgData});

  EpgModel.fromJson(dynamic json) {
    channelName = json['channel_name'];
    date = json['date'];
    if (json['epg_data'] != null) {
      epgData = [];
      json['epg_data'].forEach((v) {
        epgData!.add(EpgData.fromJson(v)); // 解析节目数据列表
      });
    }
  }

  String? channelName;
  String? date;
  List<EpgData>? epgData;

  EpgModel copyWith({String? channelName, String? date, List<EpgData>? epgData}) =>
      EpgModel(
        channelName: channelName ?? this.channelName,
        date: date ?? this.date,
        epgData: epgData ?? this.epgData,
      );
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['channel_name'] = channelName;
    map['date'] = date;
    if (epgData != null) {
      map['epg_data'] = epgData?.map((v) => v.toJson()).toList();
    }
    return map;
  }
}

/// end : "01:34"
/// start : "01:06"
/// title : "今日说法-2024-214"
class EpgData {
  EpgData({this.desc, this.end, this.start, this.title});

  EpgData.fromJson(dynamic json) {
    desc = json['desc'];
    end = json['end'];
    start = json['start'];
    title = json['title'];
  }

  String? desc;
  String? end;
  String? start;
  String? title;

  EpgData copyWith({String? desc, String? end, String? start, String? title}) =>
      EpgData(
        desc: desc ?? this.desc,
        end: end ?? this.end,
        start: start ?? this.start,
        title: title ?? this.title,
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['desc'] = desc;
    map['end'] = end;
    map['start'] = start;
    map['title'] = title;
    return map;
  }
}
