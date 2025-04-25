import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/zhConverter.dart';
import 'package:itvapp_live_tv/config.dart';

/// EPG 节目数据模型
class EpgData {
  String? desc; // 节目描述
  String? end; // 结束时间
  String? start; // 开始时间
  String? title; // 节目标题

  EpgData({this.desc, this.end, this.start, this.title});

  EpgData.fromJson(dynamic json) {
    desc = json['desc'] == '' ? null : json['desc'] as String?; // 解析节目描述
    start = json['start'] as String?; // 解析开始时间
    end = json['end'] as String?; // 解析结束时间
    title = json['title'] as String?; // 解析节目标题
    if (start != null && end != null) {
      if (!_timePatternRegExp.hasMatch(start!) || !_timePatternRegExp.hasMatch(end!)) {
        LogUtil.i('EPG 时间格式无效: start=$start, end=$end');
        start = null;
        end = null;
      }
    }
  }

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
  
  // 时间格式正则表达式，验证 HH:mm
  static final RegExp _timePatternRegExp = RegExp(r'^\d{2}:\d{2}$');
}

/// EPG 数据模型，包含频道和节目信息
class EpgModel {
  String? channelName; // 频道名称
  String? date; // 日期
  List<EpgData>? epgData; // 节目数据列表

  EpgModel({this.channelName, this.date, this.epgData});

  EpgModel.fromJson(dynamic json) {
    channelName = json['channel_name'] as String?;
    date = json['date'] as String?;
    if (json['epg_data'] != null) {
      epgData = [];
      for (var v in json['epg_data']) {
        final epgDataItem = EpgData.fromJson(v);
        if (epgDataItem.title == null || epgDataItem.start == null || epgDataItem.end == null) {
          LogUtil.i('EPG 无效数据: 缺少必要字段=$v');
          continue;
        }
        epgData!.add(epgDataItem);
      }
    }
    if (epgData == null || epgData!.isEmpty) {
      LogUtil.i('EPG 解析失败: 无有效节目, channel=$channelName, date=$date');
    }
    LogUtil.i('解析 EpgModel: channel=$channelName, date=$date, count=${epgData?.length ?? 0}');
  }

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

/// EPG 工具类，管理节目指南数据的获取、缓存和中文转换
class EpgUtil {
  EpgUtil._(); // 私有构造函数，防止实例化

  static Iterable<XmlElement>? _programmes; // 缓存解析后的 XML 节目数据
  static const String _epgFolderName = 'epg_data'; // EPG 数据存储文件夹
  static Directory? _epgBaseDir; // EPG 数据基础目录
  static ZhConverter? _zhConverter; // 缓存中文转换器实例
  
  // 正则表达式常量，避免重复创建
  static final RegExp _safeFileNameRegExp = RegExp(r'[^\w\s\-\.]'); // 清理文件名
  static final RegExp _dateValidationRegExp = RegExp(r'^\d{8}$'); // 验证日期格式
  static final RegExp _titleCleanRegExp = RegExp(r'[ -]'); // 清理标题空格和连字符
  static final RegExp _timePatternRegExp = RegExp(r'^\d{2}:\d{2}$'); // 验证时间格式

  // 初始化 EPG 文件系统
  static Future<void> init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _epgBaseDir = Directory('${appDir.path}/$_epgFolderName');
      
      if (!await _epgBaseDir!.exists()) {
        await _epgBaseDir!.create(recursive: true); // 创建 EPG 目录
      }
      
      await _cleanOldData(); // 清理过期数据
      LogUtil.i('EPG 文件系统初始化完成: ${_epgBaseDir!.path}');
    } catch (e, stackTrace) {
      LogUtil.logError('EPG 文件系统初始化失败', e, stackTrace);
    }
  }
  
  // 清理过期数据（删除当前日期前的文件夹）
  static Future<void> _cleanOldData() async {
    if (_epgBaseDir == null) return;
    
    try {
      final now = DateTime.now();
      final currentDate = DateUtil.formatDate(now, format: "yyyyMMdd");
      
      final folders = await _epgBaseDir!.list().toList();
      for (var folder in folders) {
        if (folder is Directory) {
          final folderName = folder.path.split('/').last;
          if (_isValidDateFolder(folderName) && folderName.compareTo(currentDate) < 0) {
            await folder.delete(recursive: true); // 删除过期文件夹
            LogUtil.i('删除过期 EPG 数据: $folderName');
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('清理 EPG 旧数据失败', e, stackTrace);
    }
  }
  
  // 验证日期文件夹名是否为有效格式（yyyyMMdd）
  static bool _isValidDateFolder(String folderName) {
    if (folderName.length != 8 || !_dateValidationRegExp.hasMatch(folderName)) {
      return false;
    }
    
    try {
      final year = int.parse(folderName.substring(0, 4));
      final month = int.parse(folderName.substring(4, 6));
      final day = int.parse(folderName.substring(6, 8));
      
      if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
        return false; // 日期范围无效
      }
      
      return true;
    } catch (e) {
      return false; // 解析失败
    }
  }
  
  // 获取当前日期的 EPG 目录
  static Future<Directory> _getCurrentDateFolder() async {
    if (_epgBaseDir == null) await init();
    
    final currentDate = DateUtil.formatDate(DateTime.now(), format: "yyyyMMdd");
    final dateFolder = Directory('${_epgBaseDir!.path}/$currentDate');
    if (!await dateFolder.exists()) {
      await dateFolder.create(recursive: true); // 创建日期目录
    }
    return dateFolder;
  }
  
  // 清理文件名中的非法字符
  static String _sanitizeFileName(String filename) {
    return filename.replaceAll(_safeFileNameRegExp, '_');
  }
  
  // 保存 EPG 数据到文件
  static Future<void> _saveEpgToFile(String channelKey, EpgModel model) async {
    try {
      final dateFolder = await _getCurrentDateFolder();
      final safeKey = _sanitizeFileName(channelKey);
      final file = File('${dateFolder.path}/$safeKey.json');
      
      final jsonData = jsonEncode(model.toJson());
      await file.writeAsString(jsonData);
      LogUtil.i('EPG 数据保存: ${file.path}');
    } catch (e, stackTrace) {
      LogUtil.logError('保存 EPG 数据失败: $channelKey', e, stackTrace);
    }
  }
  
  // 从文件加载 EPG 数据
  static Future<EpgModel?> _loadEpgFromFile(String channelKey) async {
    try {
      final dateFolder = await _getCurrentDateFolder();
      final safeKey = _sanitizeFileName(channelKey);
      final file = File('${dateFolder.path}/$safeKey.json');
      
      if (!await file.exists()) {
        return null; // 文件不存在
      }
      
      final jsonData = await file.readAsString();
      final model = EpgModel.fromJson(jsonDecode(jsonData));
      LogUtil.i('从文件加载 EPG: ${file.path}');
      return model;
    } catch (e, stackTrace) {
      LogUtil.logError('加载 EPG 数据失败: $channelKey', e, stackTrace);
      return null;
    }
  }

  // 从缓存获取用户语言设置
  static Locale _getUserLocaleFromCache() {
    try {
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');
      if (languageCode != null && languageCode.isNotEmpty) {
        return countryCode != null && countryCode.isNotEmpty
            ? Locale(languageCode, countryCode)
            : Locale(languageCode); // 返回缓存语言
      }
      return const Locale('en'); // 默认英语
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户语言失败', e, stackTrace);
      return const Locale('en');
    }
  }

  // 获取中文转换器实例
  static Future<ZhConverter?> _getChineseConverter() async {
    final userLocale = _getUserLocaleFromCache();
    if (!userLocale.languageCode.startsWith('zh')) {
      LogUtil.i('无需转换: 非中文语言 (${userLocale.languageCode})');
      return null;
    }
    
    String userLang = userLocale.languageCode;
    if (userLocale.countryCode != null && userLocale.countryCode!.isNotEmpty) {
      userLang = '${userLocale.languageCode}_${userLocale.countryCode}';
    }
    
    String conversionType = '';
    if (userLang.contains('TW') || userLang.contains('HK') || userLang.contains('MO')) {
      conversionType = 's2t'; // 简体转繁体
    } else if (userLang.contains('CN') || userLang == 'zh') {
      conversionType = 't2s'; // 繁体转简体
    } else {
      LogUtil.i('无需转换: 未识别中文变体 ($userLang)');
      return null;
    }
    
    if (_zhConverter == null || _zhConverter!.conversionType != conversionType) {
      _zhConverter = ZhConverter(conversionType);
      await _zhConverter!.initialize(); // 初始化转换器
    }
    
    return _zhConverter;
  }

  // 转换中文字符串
  static Future<String> _convertChineseString(String? text, ZhConverter converter) async {
    if (text == null || text.isEmpty) {
      return text ?? ''; // 空文本直接返回
    }
    try {
      return await converter.convert(text); // 执行转换
    } catch (e) {
      LogUtil.e('中文转换失败: $text, 错误=$e');
      return text;
    }
  }

  // 转换 EPG 数据中的中文内容
  static Future<EpgModel> _convertEpgModelChinese(EpgModel model) async {
    final converter = await _getChineseConverter();
    if (converter == null) {
      return model; // 无需转换
    }
    
    try {
      String? newChannelName = model.channelName;
      if (newChannelName != null && newChannelName.isNotEmpty) {
        newChannelName = await _convertChineseString(newChannelName, converter);
      }
      
      List<EpgData>? newEpgData;
      if (model.epgData != null && model.epgData!.isNotEmpty) {
        newEpgData = [];
        for (var epgData in model.epgData!) {
          final newTitle = await _convertChineseString(epgData.title, converter);
          final newDesc = await _convertChineseString(epgData.desc, converter);
          
          newEpgData.add(epgData.copyWith(
            title: newTitle.isNotEmpty ? newTitle : epgData.title,
            desc: newDesc.isNotEmpty ? newDesc : epgData.desc,
          ));
        }
      }
      
      return model.copyWith(channelName: newChannelName, epgData: newEpgData);
    } catch (e, stackTrace) {
      LogUtil.logError('EPG 中文转换失败', e, stackTrace);
      return model;
    }
  }

  // 获取 EPG 数据，优先从缓存、XML 或网络加载
  static Future<EpgModel?> getEpg(PlayModel? model, {CancelToken? cancelToken}) async {
    if (model == null) {
      LogUtil.i('获取失败: 输入模型为空');
      return null;
    }
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: 请求已取消');
      return null;
    }
    
    String channelKey = '';
    String channel = '';
    String date = '';
    final isHasXml = _programmes != null && _programmes!.isNotEmpty;

    if (model.id != null && model.id!.isNotEmpty && isHasXml) {
      channelKey = model.id!; // 使用频道 ID 作为键
    } else {
      if (model.title == null || model.title!.isEmpty) {
        LogUtil.i('获取失败: 频道标题为空');
        return null;
      }
      channel = model.title!.replaceAll(_titleCleanRegExp, '');
      date = DateUtil.formatDate(DateTime.now(), format: "yyMMdd");
      channelKey = "$date-$channel"; // 组合日期和频道名
    }

    final cachedEpg = await _loadEpgFromFile(channelKey);
    if (cachedEpg != null) {
      LogUtil.i('从缓存获取: key=$channelKey');
      return cachedEpg;
    }

    if (isHasXml) {
      final epgModel = await _parseXmlEpg(model);
      if (epgModel != null) {
        final convertedEpgModel = await _convertEpgModelChinese(epgModel);
        await _saveEpgToFile(channelKey, convertedEpgModel);
        LogUtil.i('从 XML 解析并保存: key=$channelKey');
        return convertedEpgModel;
      }
    }

    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: channel=$channel, date=$date');
      return null;
    }
    
    final epgRes = await HttpUtil().getRequest(
      '${Config.epgBaseUrl}?ch=$channel&date=$date',
      cancelToken: cancelToken, // 发起网络请求
    );
    
    if (epgRes != null) {
      final epg = EpgModel.fromJson(epgRes);
      if (epg.epgData == null || epg.epgData!.isEmpty) {
        LogUtil.i('数据无效: 无节目信息, channel=$channel, date=$date');
        return null;
      }
      
      if (epg.date == null || epg.date!.isEmpty) {
        epg.date = DateUtil.formatDate(DateTime.now(), format: "yyyy-MM-dd"); // 设置默认日期
      }
      
      final convertedEpg = await _convertEpgModelChinese(epg);
      await _saveEpgToFile(channelKey, convertedEpg);
      LogUtil.i('从网络加载并保存: key=$channelKey');
      return convertedEpg;
    }
    
    LogUtil.i('获取失败: 无有效数据, channel=$channel, date=$date');
    return null;
  }
  
  // 从 XML 解析 EPG 数据
  static Future<EpgModel?> _parseXmlEpg(PlayModel model) async {
    if (_programmes == null || _programmes!.isEmpty || model.id == null) {
      return null; // XML 数据或频道 ID 无效
    }
    
    final epgModel = EpgModel(
      channelName: model.title ?? '未知频道', 
      epgData: [],
      date: DateUtil.formatDate(DateTime.now(), format: "yyyy-MM-dd"),
    );
    
    final matchedProgrammes = _programmes!.where((programme) => 
      programme.getAttribute('channel') == model.id);
      
    if (matchedProgrammes.isEmpty) {
      LogUtil.i('XML 匹配失败: 未找到节目, channel=${model.id}');
      return null;
    }
    
    for (var programme in matchedProgrammes) {
      final start = programme.getAttribute('start');
      final stop = programme.getAttribute('stop');
      if (start == null || stop == null) {
        LogUtil.i('解析失败: 缺少 start/stop, channel=${model.id}');
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
        
        if (!_timePatternRegExp.hasMatch(dateStart) || !_timePatternRegExp.hasMatch(dateEnd)) {
          LogUtil.i('时间格式无效: start=$dateStart, end=$dateEnd, channel=${model.id}');
          continue;
        }
        
        final titleElements = programme.findAllElements('title');
        if (titleElements.isEmpty) {
          LogUtil.i('解析失败: 缺少标题, channel=${model.id}, start=$start');
          continue;
        }
        
        final title = titleElements.first.innerText;
        epgModel.epgData!.add(EpgData(title: title, start: dateStart, end: dateEnd));
      } catch (e) {
        LogUtil.e('解析失败: start=$start, stop=$stop, channel=${model.id}, 错误=$e');
        continue;
      }
    }
    
    if (epgModel.epgData!.isEmpty) {
      LogUtil.i('数据无效: 无有效节目, channel=${model.id}');
      return null;
    }
    
    return epgModel;
  }

  // 加载 EPG XML 文件，支持重试
  static Future<void> loadEPGXML(String url) async {
    int index = 0;
    const int maxRetries = 3;
    final uStr = url.replaceAll('/h', ',h');
    final urlLink = uStr.split(','); // 分割 URL 列表
    XmlDocument? tempXmlDocument;
    final failedUrls = <String>[];

    while (tempXmlDocument == null && index < urlLink.length && index < maxRetries) {
      final currentUrl = urlLink[index];
      final res = await HttpUtil().getRequest(currentUrl);
      if (res != null) {
        try {
          tempXmlDocument = XmlDocument.parse(res.toString()); // 解析 XML
        } catch (e) {
          LogUtil.e('XML 解析失败: url=$currentUrl, 错误=$e');
          failedUrls.add(currentUrl);
          index += 1;
        }
      } else {
        LogUtil.i('XML 请求失败: url=$currentUrl');
        failedUrls.add(currentUrl);
        index += 1;
      }
    }
    if (tempXmlDocument == null) {
      LogUtil.e('XML 加载失败: 所有 URL 无效, url=$url, 失败=$failedUrls');
    }
    _programmes = tempXmlDocument?.findAllElements('programme'); // 缓存节目数据
  }

  // 重置 EPG XML 数据
  static void resetEPGXML() {
    _programmes = null; // 清空缓存的节目数据
  }
}
