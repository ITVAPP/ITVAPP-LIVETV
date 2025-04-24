import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:opencc/opencc.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/config.dart'; // Added for Config

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

// 缓存条目，记录 EPG 数据和存储时间
class _EpgCacheEntry {
  final EpgModel model;
  final DateTime timestamp;

  _EpgCacheEntry(this.model, this.timestamp);
}

/// channel_name : "CCTV1"
/// date : ""
/// epg_data : []
class EpgUtil {
  EpgUtil._(); // 私有构造函数，防止实例化

  static final Map<String, _EpgCacheEntry> epgCacheMap = <String, _EpgCacheEntry>{}; // 缓存 EPG 数据，包含时间戳
  static Map<String, List<XmlElement>>? _programmesByChannel; // 按频道分区的节目数据
  static const int _maxCacheSize = 100; // 缓存最大容量限制
  static const Duration _cacheTTL = Duration(hours: 24); // 缓存有效期 24 小时

  // 获取语言转换设置，集中处理语言逻辑
  static ({String? conversionType, String? userLang}) _getLanguageSettings(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final userLocale = languageProvider.currentLocale;
    String? userLang;
    String? conversionType;

    if (userLocale.languageCode.startsWith('zh')) {
      userLang = userLocale.languageCode == 'zh' && userLocale.countryCode != null
          ? 'zh_${userLocale.countryCode}' // 标准 zh + 国家代码
          : userLocale.languageCode; // 直接使用 languageCode（如 zh, zh_CN, zh_TW）
      conversionType = _getConversionType(userLang);
    }
    return (conversionType: conversionType, userLang: userLang);
  }

  // 获取语言转换类型
  static String? _getConversionType(String userLang) {
    const conversionMap = {
      'zh_CN': 'zhHant2Hans', // 简体
      'zh_TW': 'zhHans2Hant', // 繁体
      'zh_HK': 'zhHans2Hant', // 繁体
      'zh': 'zhHant2Hans', // 默认简体
    };
    return conversionMap[userLang];
  }

  // 简繁体转换
  static String _convertString(String text, String conversionType) {
    try {
      ConversionType? type;
      if (conversionType == 'zhHans2Hant') {
        type = ConversionType.zhHans2Hant;
      } else if (conversionType == 'zhHant2Hans') {
        type = ConversionType.zhHant2Hans;
      } else {
        LogUtil.i('无效的转换类型: $conversionType，跳过转换');
        return text;
      }

      final converter = createConverter(type);
      if (converter == null) {
        LogUtil.i('无法创建转换器，跳过转换');
        return text;
      }

      return converter.convert(text);
    } catch (e, stackTrace) {
      LogUtil.logError('简繁体转换失败: text=$text, type=$conversionType', e, stackTrace);
      return text; // 转换失败返回原文本
    }
  }

  // 批量转换 EPG 数据的简繁体，减少转换调用
  static EpgModel _convertEpgModel(EpgModel model, String conversionType, String userLang) {
    try {
      // 批量收集 title 和 desc
      List<String> textsToConvert = [];
      List<bool> isTitle = [];
      model.epgData?.forEach((data) {
        if (data.title != null) {
          textsToConvert.add(data.title!);
          isTitle.add(true);
        }
        if (data.desc != null) {
          textsToConvert.add(data.desc!);
          isTitle.add(false);
        }
      });

      // 批量转换
      List<String> convertedTexts = textsToConvert
          .asMap()
          .map((index, text) => MapEntry(index, _convertString(text, conversionType)))
          .values
          .toList();

      // 重新构建 epgData
      List<EpgData> convertedData = [];
      int textIndex = 0;
      for (var data in model.epgData ?? []) {
        String? newTitle = data.title != null ? convertedTexts[textIndex++] : null;
        String? newDesc = data.desc != null ? convertedTexts[textIndex++] : null;
        convertedData.add(data.copyWith(title: newTitle, desc: newDesc));
      }

      return model.copyWith(epgData: convertedData);
    } catch (e, stackTrace) {
      LogUtil.logError('EPG 数据转换失败: type=$conversionType, userLang=$userLang', e, stackTrace);
      return model; // 转换失败返回原始数据
    }
  }

  // 清理缓存，移除过期或超限条目
  static void _cleanCache() {
    final now = DateTime.now();
    // 移除过期缓存
    epgCacheMap.removeWhere((key, entry) => now.difference(entry.timestamp) > _cacheTTL);
    // 移除超限缓存（按时间戳排序，保留最新）
    if (epgCacheMap.length > _maxCacheSize) {
      final sortedEntries = epgCacheMap.entries.toList()
        ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
      epgCacheMap.clear();
      for (var entry in sortedEntries.take(_maxCacheSize)) {
        epgCacheMap[entry.key] = entry.value;
      }
      LogUtil.i('缓存超限，已清理至 $_maxCacheSize 条');
    }
  }

  // 获取 EPG 数据，支持缓存、XML 和网络请求
  static Future<EpgModel?> getEpg(PlayModel? model, {BuildContext? context, CancelToken? cancelToken}) async {
    // 检查取消状态
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('EPG 获取取消：请求已取消');
      return null;
    }

    if (model == null) {
      LogUtil.i('EPG 获取失败：输入模型为空');
      return null;
    }

    String channelKey = '';
    String channel = '';
    String date = '';
    final isHasXml = _programmesByChannel != null && _programmesByChannel!.isNotEmpty;

    if (model.id != null && model.id!.isNotEmpty && isHasXml) {
      channelKey = model.id!.toLowerCase(); // 规范化缓存键
    } else {
      if (model.title == null) {
        LogUtil.i('EPG 获取失败：频道标题为空');
        return null;
      }
      channel = model.title!.replaceAll(RegExp(r'[ -]'), '').toLowerCase(); // 清理标题并规范化
      date = DateUtil.formatDate(DateTime.now(), format: "yyMMdd");
      channelKey = "$date-$channel";
    }

    // 检查缓存
    if (epgCacheMap.containsKey(channelKey)) {
      final entry = epgCacheMap[channelKey]!;
      if (DateTime.now().difference(entry.timestamp) <= _cacheTTL) {
        LogUtil.i('命中缓存: $channelKey');
        return entry.model;
      } else {
        epgCacheMap.remove(channelKey); // 移除过期缓存
        LogUtil.i('缓存已过期，重新获取: $channelKey');
      }
    }

    EpgModel? epgModel;

    if (isHasXml) {
      epgModel = EpgModel(channelName: model.title ?? '未知频道', epgData: []);
      final programmes = _programmesByChannel![model.id?.toLowerCase() ?? ''] ?? [];
      for (var programme in programmes) {
        if (cancelToken?.isCancelled ?? false) {
          LogUtil.i('EPG 解析取消：请求已取消，channel=${model.id}');
          return null;
        }
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');
        if (start == null || stop == null) {
          LogUtil.i('EPG 解析失败：节目缺少 start 或 stop，channel=${model.id}');
          continue;
        }
        try {
          final dateStart = DateUtil.formatDate(
            DateUtil.parseCustomDateTimeString(start),
            format: "HH:mm",
          );
          final dateEnd = DateUtil.formatDate(
            DateUtil.parseCustomDateTimeString(stop),
            format: "HH:mm",
          );
          final titleElements = programme.findAllElements('title');
          if (titleElements.isEmpty) {
            LogUtil.i('EPG 解析失败：节目缺少标题，channel=${model.id}, start=$start');
            continue;
          }
          final title = titleElements.first.innerText;
          final descElements = programme.findAllElements('desc');
          final desc = descElements.isNotEmpty ? descElements.first.innerText : null;
          epgModel.epgData!.add(EpgData(title: title, desc: desc, start: dateStart, end: dateEnd));
        } catch (e, stackTrace) {
          LogUtil.logError('EPG 时间解析失败: start=$start, stop=$stop', e, stackTrace);
          continue;
        }
      }
      if (epgModel.epgData!.isEmpty) {
        LogUtil.i('EPG 数据无效：无有效节目，channel=${model.id}');
        return null;
      }
    } else {
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('EPG 获取取消：请求已取消，channel=$channel, date=$date');
        return null;
      }
      
      final epgRes = await HttpUtil().getRequest(
        '${Config.epgBaseUrl}?ch=$channel&date=$date',
        cancelToken: cancelToken,
      );
      
      if (epgRes != null) {
        epgModel = EpgModel.fromJson(epgRes);
        if (epgModel.epgData == null || epgModel.epgData!.isEmpty) {
          LogUtil.i('EPG 数据无效：无节目信息，channel=$channel, date=$date');
          return null;
        }
      } else {
        LogUtil.i('EPG 获取失败：无有效数据，channel=$channel, date=$date');
        return null;
      }
    }

    // 应用语言转换
    if (epgModel != null) {
      if (context != null) {
        final languageSettings = _getLanguageSettings(context);
        final conversionType = languageSettings.conversionType;
        final userLang = languageSettings.userLang;
        if (conversionType != null && userLang != null) {
          LogUtil.i('正在对 EPG 数据进行中文转换: $userLang ($conversionType)');
          epgModel = _convertEpgModel(epgModel, conversionType, userLang);
          LogUtil.i('EPG 数据中文转换完成');
        } else {
          String reason = userLang == null
              ? '用户语言非中文 (${context.read<LanguageProvider>().currentLocale.languageCode})'
              : '无匹配的转换类型';
          LogUtil.i('无需对 EPG 数据进行中文转换: $reason');
        }
      } else {
        LogUtil.i('未提供 BuildContext，跳过 EPG 数据中文转换');
      }
      _cleanCache(); // 清理缓存
      epgCacheMap[channelKey] = _EpgCacheEntry(epgModel, DateTime.now()); // 缓存数据
      LogUtil.i('加载并缓存新的 EPG 数据: $channelKey');
      return epgModel;
    }

    return null;
  }

  // 加载 EPG XML 文件，支持重试
  static Future<void> loadEPGXML(String url) async {
    int index = 0;
    const int maxRetries = 3;
    final uStr = url.replaceAll('/h', ',h');
    final urlLink = uStr.split(',');
    XmlDocument? tempXmlDocument;

    while (tempXmlDocument == null && index < urlLink.length && index < maxRetries) {
      try {
        final res = await HttpUtil().getRequest(urlLink[index]);
        if (res != null) {
          tempXmlDocument = XmlDocument.parse(res.toString());
        } else {
          LogUtil.i('EPG XML 请求失败: url=${urlLink[index]}');
          index += 1;
        }
      } catch (e, stackTrace) {
        LogUtil.logError('EPG XML 解析或请求失败: url=${urlLink[index]}', e, stackTrace);
        index += 1;
      }
    }

    if (tempXmlDocument == null) {
      LogUtil.e('EPG XML 加载失败：所有 URL 无效，url=$url');
      _programmesByChannel = null; // 加载失败重置
      return;
    }

    // 按频道分区
    _programmesByChannel = {};
    for (var programme in tempXmlDocument.findAllElements('programme')) {
      final channel = programme.getAttribute('channel')?.toLowerCase();
      if (channel != null) {
        _programmesByChannel!.putIfAbsent(channel, () => []).add(programme);
      }
    }
    LogUtil.i('EPG XML 加载成功: 频道数=${_programmesByChannel!.length}');
  }

  // 重置 EPG XML 数据
  static void resetEPGXML() {
    _programmesByChannel = null;
    LogUtil.i('EPG XML 数据已重置');
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
      final invalidItems = <String>[];
      for (var v in json['epg_data']) {
        final epgDataItem = EpgData.fromJson(v);
        if (epgDataItem.title == null || epgDataItem.start == null || epgDataItem.end == null) {
          invalidItems.add(v.toString());
          continue;
        }
        epgData!.add(epgDataItem);
      }
      if (invalidItems.isNotEmpty) {
        LogUtil.i('EPG JSON 无效：缺少必要字段，数据=$invalidItems');
      }
    }
    if (epgData == null || epgData!.isEmpty) {
      LogUtil.i('EPG JSON 解析失败：无有效节目，channel=$channelName, date=$date');
    }
    LogUtil.i('解析 EpgModel: channel=$channelName, date=$date, epgDataCount=${epgData?.length ?? 0}');
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
    desc = json['desc'] == '' ? null : json['desc'] as String?;
    start = json['start'] as String?;
    end = json['end'] as String?;
    title = json['title'] as String?;
    if (start != null && end != null) {
      final timePattern = RegExp(r'^\d{2}:\d{2}$');
      if (!timePattern.hasMatch(start!) || !timePattern.hasMatch(end!)) {
        start = null;
        end = null;
      }
    }
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
