import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:opencc/opencc.dart';
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
  static const int _maxCacheSize = 100; // 缓存最大容量限制
  static const Duration _cacheTTL = Duration(hours: 24); // 缓存有效期 24 小时

  // 清理过期或超量缓存
  static void _cleanCache() {
    final now = DateTime.now();
    epgCacheMap.removeWhere((key, value) {
      // 检查缓存是否过期
      if (value.date != null) {
        try {
          final cacheTime = DateUtil.parseCustomDateTimeString(value.date!);
          return now.difference(cacheTime) > _cacheTTL;
        } catch (e) {
          LogUtil.e('解析缓存日期失败: date=${value.date}, 错误=$e');
          return false;
        }
      }
      return false;
    });
    // 移除超量缓存
    while (epgCacheMap.length > _maxCacheSize) {
      final oldestKey = epgCacheMap.keys.first;
      epgCacheMap.remove(oldestKey);
    }
  }

  /// 从SpUtil缓存获取用户语言设置
  static Locale _getUserLocaleFromCache() {
    try {
      // 从持久化存储读取语言和国家代码
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');
      
      if (languageCode != null && languageCode.isNotEmpty) {
        // 若语言代码有效，返回保存的语言环境
        if (countryCode != null && countryCode.isNotEmpty) {
          return Locale(languageCode, countryCode);
        } else {
          return Locale(languageCode);
        }
      }
      
      // 如果没有存储的语言设置，使用默认英语
      return const Locale('en');
    } catch (e, stackTrace) {
      LogUtil.logError('从缓存获取用户语言设置失败', e, stackTrace);
      // 发生错误时使用默认英语
      return const Locale('en');
    }
  }

  /// 获取需要的中文转换器，如果不需要转换则返回null
  static ZhConverter? _getChineseConverter() {
    // 获取用户语言设置
    final userLocale = _getUserLocaleFromCache();
    
    // 如果不是中文语言，不需要转换
    if (!userLocale.languageCode.startsWith('zh')) {
      LogUtil.i('EPG数据无需中文转换：用户语言不是中文 (${userLocale.languageCode})');
      return null;
    }
    
    // 构造完整的语言代码
    String userLang = userLocale.languageCode;
    if (userLocale.countryCode != null && userLocale.countryCode!.isNotEmpty) {
      userLang = '${userLocale.languageCode}_${userLocale.countryCode}';
    }
    
    // 根据用户语言决定转换方向
    if (userLang.contains('TW') || userLang.contains('HK') || userLang.contains('MO')) {
      // 如果用户使用繁体中文，将简体转换为繁体
      LogUtil.i('EPG数据需要转换：简体转繁体 (用户语言=$userLang)');
      return ZhConverter('s2t');
    } else if (userLang.contains('CN') || userLang == 'zh') {
      // 如果用户使用简体中文，将繁体转换为简体
      LogUtil.i('EPG数据需要转换：繁体转简体 (用户语言=$userLang)');
      return ZhConverter('t2s');
    }
    
    // 其他情况不需要转换
    LogUtil.i('EPG数据无需中文转换：未识别的中文变体 (用户语言=$userLang)');
    return null;
  }

  /// 转换EPG数据中的中文（标题和描述）
  static EpgModel _convertEpgModelChinese(EpgModel model) {
    final converter = _getChineseConverter();
    if (converter == null) {
      return model; // 不需要转换，直接返回原始数据
    }
    
    try {
      // 转换频道名称
      String? newChannelName = model.channelName;
      if (newChannelName != null && newChannelName.isNotEmpty) {
        newChannelName = converter.convert(newChannelName);
      }
      
      // 转换节目数据
      List<EpgData>? newEpgData;
      if (model.epgData != null && model.epgData!.isNotEmpty) {
        newEpgData = model.epgData!.map((epgData) {
          // 转换标题
          String? newTitle = epgData.title;
          if (newTitle != null && newTitle.isNotEmpty) {
            newTitle = converter.convert(newTitle);
          }
          
          // 转换描述
          String? newDesc = epgData.desc;
          if (newDesc != null && newDesc.isNotEmpty) {
            newDesc = converter.convert(newDesc);
          }
          
          return epgData.copyWith(
            title: newTitle,
            desc: newDesc
          );
        }).toList();
      }
      
      // 创建新的EPG模型
      return model.copyWith(
        channelName: newChannelName,
        epgData: newEpgData
      );
    } catch (e, stackTrace) {
      LogUtil.logError('EPG中文转换失败，返回原始数据', e, stackTrace);
      return model; // 转换失败，返回原始数据
    }
  }

  // 获取 EPG 数据，支持缓存、XML 和网络请求
  static Future<EpgModel?> getEpg(PlayModel? model, {CancelToken? cancelToken}) async {
    if (model == null) {
      LogUtil.i('EPG 获取失败：输入模型为空');
      return null; // 输入模型为空，直接返回
    }

    String channelKey = '';
    String channel = '';
    String date = '';
    final isHasXml = _programmes != null && _programmes!.isNotEmpty; // 检查 XML 数据是否可用

    if (model.id != null && model.id!.isNotEmpty && isHasXml) {
      channelKey = model.id!; // 使用频道 ID 作为缓存键
    } else {
      if (model.title == null) {
        LogUtil.i('EPG 获取失败：频道标题为空');
        return null; // 标题为空，直接返回
      }
      channel = model.title!.replaceAll(RegExp(r'[ -]'), ''); // 清理标题中的空格和连字符
      date = DateUtil.formatDate(DateTime.now(), format: "yyMMdd"); // 获取当前日期
      channelKey = "$date-$channel"; // 使用日期和频道名组合键
    }

    if (epgCacheMap.containsKey(channelKey)) {
      return epgCacheMap[channelKey]!; // 返回缓存数据
    }

    if (isHasXml) {
      EpgModel epgModel = EpgModel(channelName: model.title ?? '未知频道', epgData: []);
      // 过滤匹配当前频道的节目数据
      final matchedProgrammes = _programmes!.where((programme) => programme.getAttribute('channel') == model.id);
      for (var programme in matchedProgrammes) {
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');
        if (start == null || stop == null) {
          LogUtil.i('EPG 解析失败：节目缺少 start 或 stop，channel=${model.id}');
          continue;
        }
        final dateStart = DateUtil.formatDate(DateUtil.parseCustomDateTimeString(start), format: "HH:mm"); // 格式化开始时间
        final dateEnd = DateUtil.formatDate(DateUtil.parseCustomDateTimeString(stop), format: "HH:mm"); // 格式化结束时间
        final titleElements = programme.findAllElements('title');
        if (titleElements.isEmpty) {
          LogUtil.i('EPG 解析失败：节目缺少标题，channel=${model.id}, start=$start');
          continue;
        }
        final title = titleElements.first.innerText; // 获取节目标题
        epgModel.epgData!.add(EpgData(title: title, start: dateStart, end: dateEnd)); // 添加节目数据
      }
      if (epgModel.epgData!.isEmpty) {
        LogUtil.i('EPG 数据无效：无有效节目，channel=${model.id}');
        return null; // 无节目数据返回 null
      }
      
      // 应用中文转换
      final convertedEpgModel = _convertEpgModelChinese(epgModel);
      
      _cleanCache(); // 清理缓存
      epgCacheMap[channelKey] = convertedEpgModel; // 缓存转换后的 EPG 数据
      return convertedEpgModel;
    }

    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('EPG 获取取消：请求已取消，channel=$channel, date=$date');
      return null; // 请求取消返回 null
    }
    
    final epgRes = await HttpUtil().getRequest(
      '${Config.epgBaseUrl}?ch=$channel&date=$date', // 构造 EPG 请求 URL
      cancelToken: cancelToken, // 支持取消请求
    );
    
    if (epgRes != null) {
      final epg = EpgModel.fromJson(epgRes); // 解析 JSON 数据
      if (epg.epgData == null || epg.epgData!.isEmpty) {
        LogUtil.i('EPG 数据无效：无节目信息，channel=$channel, date=$date');
        return null;
      }
      
      // 应用中文转换
      final convertedEpg = _convertEpgModelChinese(epg);
      
      _cleanCache(); // 清理缓存
      epgCacheMap[channelKey] = convertedEpg; // 缓存转换后的结果
      LogUtil.i('加载并缓存新的 EPG 数据: $channelKey'); // 添加这行日志，确认数据被成功处理
      return convertedEpg;
    }
    LogUtil.i('EPG 获取失败：无有效数据，channel=$channel, date=$date');
    return null; // 无有效数据返回 null
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
          LogUtil.e('EPG XML 解析失败: url=${urlLink[index]}, 错误=$e');
          index += 1; // 解析失败，尝试下一个 URL
        }
      } else {
        LogUtil.i('EPG XML 请求失败: url=${urlLink[index]}');
        index += 1; // 请求失败，尝试下一个 URL
      }
    }
    if (tempXmlDocument == null) {
      LogUtil.e('EPG XML 加载失败：所有 URL 无效，url=$url');
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
    channelName = json['channel_name'] as String?;
    date = json['date'] as String?;
    if (json['epg_data'] != null) {
      epgData = [];
      for (var v in json['epg_data']) {
        final epgDataItem = EpgData.fromJson(v);
        if (epgDataItem.title == null || epgDataItem.start == null || epgDataItem.end == null) {
          LogUtil.i('EPG JSON 无效：缺少必要字段，数据=$v');
          continue;
        }
        epgData!.add(epgDataItem);
      }
    }
    if (epgData == null || epgData!.isEmpty) {
      LogUtil.i('EPG JSON 解析失败：无有效节目，channel=$channelName, date=$date');
    }
    LogUtil.i('解析 EpgModel: channel=$channelName, date=$date, epgDataCount=${epgData?.length ?? 0}');
  }

  String? channelName; // 频道名称
  String? date; // 日期
  List<EpgData>? epgData; // 节目数据列表

  // 复制模型并更新指定字段
  EpgModel copyWith({String? channelName, String? date, List<EpgData>? epgData}) =>
      EpgModel(
        channelName: channelName ?? this.channelName,
        date: date ?? this.date,
        epgData: epgData ?? this.epgData,
      );

  // 转换为 JSON 格式
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
    desc = json['desc'] == '' ? null : json['desc'] as String?; // 节目描述
    start = json['start'] as String?; // 开始时间
    end = json['end'] as String?; // 结束时间
    title = json['title'] as String?; // 节目标题
    if (start != null && end != null) {
      final timePattern = RegExp(r'^\d{2}:\d{2}$');
      if (!timePattern.hasMatch(start!) || !timePattern.hasMatch(end!)) {
        LogUtil.i('EPG JSON 时间格式无效: start=$start, end=$end');
        start = null;
        end = null;
      }
    }
  }

  String? desc; // 节目描述
  String? end; // 结束时间
  String? start; // 开始时间
  String? title; // 节目标题

  // 复制数据并更新指定字段
  EpgData copyWith({String? desc, String? end, String? start, String? title}) =>
      EpgData(
        desc: desc ?? this.desc,
        end: end ?? this.end,
        start: start ?? this.start,
        title: title ?? this.title,
      );

  // 转换为 JSON 格式
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['desc'] = desc;
    map['end'] = end;
    map['start'] = start;
    map['title'] = title;
    return map;
  }
}
