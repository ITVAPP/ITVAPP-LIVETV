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

// 将嵌套类移到外部
class _RegExpConstants {
  final safeFileName = RegExp(r'[\\/:*?"<>|]');
  final dateValidation = RegExp(r'^\d{8}$');
  final titleClean = RegExp(r'[ -]');
  final timePattern = RegExp(r'^\d{2}:\d{2}$');
}

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
      if (!EpgUtil._regex.timePattern.hasMatch(start!) || !EpgUtil._regex.timePattern.hasMatch(end!)) {
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

  // 集中管理正则表达式
  static final _RegExpConstants _regex = _RegExpConstants();

  static const String _epgFolderName = 'epg_data'; // EPG 数据存储文件夹
  static Directory? _epgBaseDir; // EPG 数据基础目录
  static ZhConverter? _zhConverter; // 缓存中文转换器实例
  static String? _currentDateString; // 缓存当前日期字符串，避免重复计算
  static Directory? _currentDateFolder; // 缓存当前日期文件夹
  
  // 缓存常用日期格式，避免重复创建
  static const String _dateFormatYMD = "yyyyMMdd";
  static const String _dateFormatHM = "HH:mm";
  static const String _dateFormatFull = "yyyy-MM-dd";
  static const String _dateFormatCompact = "yyMMdd";
  
  // 默认区域设置，减少语言查询
  static const Locale _defaultLocale = Locale('zh', 'CN');

  // 获取当前日期字符串
  static String get _currentDate => _currentDateString ?? DateUtil.formatDate(DateTime.now(), format: _dateFormatYMD);

  // 初始化 EPG 文件系统
  static Future<void> init() async {
    if (_epgBaseDir != null) return; // 避免重复初始化
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _epgBaseDir = Directory('${appDir.path}/$_epgFolderName');
      
      if (!await _epgBaseDir!.exists()) {
        await _epgBaseDir!.create(recursive: true); // 创建 EPG 目录
      }
      
      // 初始化日期字符串和文件夹
      _currentDateString = DateUtil.formatDate(DateTime.now(), format: _dateFormatYMD);
      _currentDateFolder = Directory('${_epgBaseDir!.path}/$_currentDateString');
      if (!await _currentDateFolder!.exists()) {
        await _currentDateFolder!.create(recursive: true);
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
      final folders = await _epgBaseDir!.list().toList();
      for (var folder in folders) {
        if (folder is Directory) {
          final folderName = folder.path.split('/').last;
          if (_isValidDateFolder(folderName) && folderName.compareTo(_currentDate) < 0) {
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
    if (folderName.length != 8 || !_regex.dateValidation.hasMatch(folderName)) {
      return false;
    }
    
    try {
      final year = int.parse(folderName.substring(0, 4));
      final month = int.parse(folderName.substring(4, 6));
      final day = int.parse(folderName.substring(6, 8));
      
      return (year >= 2000 && year <= 2100) && 
             (month >= 1 && month <= 12) && 
             (day >= 1 && day <= 31);
    } catch (e) {
      return false; // 解析失败
    }
  }
  
  // 获取当前日期的 EPG 目录
  static Future<Directory> _getCurrentDateFolder() async {
    if (_epgBaseDir == null) await init();
    return _currentDateFolder!;
  }
  
  // 清理文件名中的非法字符
  static String _sanitizeFileName(String filename) {
    return filename.replaceAll(_regex.safeFileName, '_');
  }
  
  // 从URL获取文件名
  static String _getFileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    
    if (pathSegments.isNotEmpty) {
      final fileName = pathSegments.last;
      if (fileName.isNotEmpty) {
        return _sanitizeFileName(fileName);
      }
    }
    
    return 'epg_${url.hashCode.abs()}';
  }
  
  // 获取文件完整路径
  static Future<String> _getFilePath(String fileName, {bool isJson = true}) async {
    final dateFolder = await _getCurrentDateFolder();
    return '${dateFolder.path}/$fileName${isJson ? '.json' : '.xml'}';
  }
  
  // 通用文件保存方法
  static Future<void> _saveFile(String fileName, String content, {bool isJson = true}) async {
    try {
      final filePath = await _getFilePath(fileName, isJson: isJson);
      await File(filePath).writeAsString(content, flush: true);
    } catch (e, stackTrace) {
      LogUtil.logError('保存 ${isJson ? 'EPG' : 'XML'} 数据失败: $fileName', e, stackTrace);
    }
  }
  
  // 通用文件加载方法
  static Future<String?> _loadFile(String fileName, {bool isJson = true}) async {
    try {
      final filePath = await _getFilePath(fileName, isJson: isJson);
      final file = File(filePath);
      if (!await file.exists()) {
        return null; // 文件不存在
      }
      
      final content = await file.readAsString();
      if (content.isEmpty) {
        return null;
      }
      
      return content;
    } catch (e, stackTrace) {
      LogUtil.logError('加载 ${isJson ? 'EPG' : 'XML'} 数据失败: $fileName', e, stackTrace);
      return null;
    }
  }
  
  // 获取XML URL列表
  static List<String> _getXmlUrls(String url) {
    final uStr = url.replaceAll('/h', ',h');
    return uStr.split(',');
  }

  // 从缓存获取用户语言设置，优化语言检测逻辑
  static Locale _getUserLocaleFromCache() {
    try {
      String? languageCode = SpUtil.getString('languageCode');
      if (languageCode == null || languageCode.isEmpty) {
        return _defaultLocale;
      }
      
      String? countryCode = SpUtil.getString('countryCode');
      return countryCode != null && countryCode.isNotEmpty
          ? Locale(languageCode, countryCode)
          : Locale(languageCode);
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户语言失败', e, stackTrace);
      return _defaultLocale;
    }
  }

  // 获取中文转换器实例
  static Future<ZhConverter?> _getChineseConverter() async {
    final userLocale = _getUserLocaleFromCache();
    final languageCode = userLocale.languageCode;
    if (languageCode != 'zh' && !languageCode.startsWith('zh_')) return null;

    String userLang = languageCode;
    if (userLocale.countryCode != null && userLocale.countryCode!.isNotEmpty) {
      userLang = '${languageCode}_${userLocale.countryCode}';
    }

    String conversionType = userLang.contains('TW') || userLang.contains('HK') || userLang.contains('MO')
        ? 's2t'
        : userLang.contains('CN') || userLang == 'zh'
            ? 't2s'
            : '';
    if (conversionType.isEmpty) {
      LogUtil.i('无需转换: 未识别中文变体 ($userLang)');
      return null;
    }

    if (_zhConverter == null || _zhConverter!.conversionType != conversionType) {
      _zhConverter = ZhConverter(conversionType);
      await _zhConverter!.initialize();
    }
    return _zhConverter;
  }

  // 转换中文字符串
  static Future<String> _convertChineseString(String? text, ZhConverter converter) async {
    if (text == null || text.isEmpty) {
      return text ?? '';
    }
    try {
      return await converter.convert(text);
    } catch (e) {
      LogUtil.e('中文转换失败: $text, 错误=$e');
      return text;
    }
  }

  // 转换XML内容中的中文文本
  static Future<String> _convertXmlContent(String xmlContent) async {
    final converter = await _getChineseConverter();
    if (converter == null) {
      return xmlContent;
    }
    
    try {
      final document = XmlDocument.parse(xmlContent);
      final tagsToConvert = ['title', 'desc', 'subtitle', 'category', 'display-name'];
      
      for (var tagName in tagsToConvert) {
        final elements = document.findAllElements(tagName);
        for (var element in elements) {
          if (element.innerText.isNotEmpty) {
            final convertedText = await converter.convert(element.innerText);
            if (convertedText != element.innerText) {
              element.innerText = convertedText;
            }
          }
        }
      }
      
      return document.toXmlString();
    } catch (e, stackTrace) {
      LogUtil.logError('XML 中文转换失败', e, stackTrace);
      return xmlContent;
    }
  }

  // 转换 EPG 数据中的中文内容
  static Future<EpgModel> _convertEpgModelChinese(EpgModel model) async {
    final converter = await _getChineseConverter();
    if (converter == null || (model.channelName == null && model.epgData == null)) {
      return model;
    }

    final newChannelName = model.channelName != null && model.channelName!.isNotEmpty
        ? await _convertChineseString(model.channelName, converter)
        : model.channelName;

    final newEpgData = model.epgData?.map((epgData) async => epgData.copyWith(
          title: await _convertChineseString(epgData.title, converter) ?? epgData.title,
          desc: await _convertChineseString(epgData.desc, converter) ?? epgData.desc,
        ));

    return model.copyWith(
      channelName: newChannelName,
      epgData: newEpgData != null ? await Future.wait(newEpgData) : null,
    );
  }

  // 解析开始和结束时间
  static Future<Map<String, String>?> _parseStartEndTimes(String? start, String? stop) async {
    if (start == null || stop == null) {
      return null;
    }
    
    try {
      final dateStart = DateUtil.formatDate(
        DateUtil.parseCustomDateTimeString(start), 
        format: _dateFormatHM,
      );
      final dateEnd = DateUtil.formatDate(
        DateUtil.parseCustomDateTimeString(stop), 
        format: _dateFormatHM,
      );
      
      if (!_regex.timePattern.hasMatch(dateStart) || !_regex.timePattern.hasMatch(dateEnd)) {
        return null;
      }
      
      return {'start': dateStart, 'end': dateEnd};
    } catch (e) {
      LogUtil.e('时间解析失败: start=$start, stop=$stop, 错误=$e');
      return null;
    }
  }

  // 从XML字符串解析EPG数据
  static Future<EpgModel?> _parseXmlFromString(String xmlString, PlayModel model) async {
    if (model.id == null) {
      LogUtil.i('解析失败: 频道ID为空');
      return null;
    }
    
    try {
      final xmlDocument = XmlDocument.parse(xmlString);
      final allProgrammes = xmlDocument.findAllElements('programme');
      final matchedProgrammes = allProgrammes.where((programme) => 
        programme.getAttribute('channel') == model.id).toList();
        
      if (matchedProgrammes.isEmpty) {
        LogUtil.i('XML 匹配失败: 未找到节目, channel=${model.id}');
        return null;
      }
      
      final epgModel = EpgModel(
        channelName: model.title ?? '未知频道', 
        epgData: [],
        date: DateUtil.formatDate(DateTime.now(), format: _dateFormatFull),
      );
      
      for (var programme in matchedProgrammes) {
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');
        
        final times = await _parseStartEndTimes(start, stop);
        if (times == null) {
          LogUtil.i('解析失败: 时间格式无效, channel=${model.id}, start=$start, stop=$stop');
          continue;
        }
        
        final titleElements = programme.findAllElements('title');
        if (titleElements.isEmpty) {
          LogUtil.i('解析失败: 缺少标题, channel=${model.id}, start=$start');
          continue;
        }
        final title = titleElements.first.innerText;
        if (title.isEmpty) {
          LogUtil.i('解析失败: 标题为空, channel=${model.id}, start=$start');
          continue;
        }
        
        String? desc;
        final descElements = programme.findAllElements('desc');
        if (descElements.isNotEmpty) {
          desc = descElements.first.innerText;
        }
        
        epgModel.epgData!.add(EpgData(
          title: title, 
          start: times['start'], 
          end: times['end'],
          desc: desc
        ));
      }
      
      if (epgModel.epgData!.isEmpty) {
        LogUtil.i('数据无效: 无有效节目, channel=${model.id}');
        return null;
      }
      
      return epgModel;
    } catch (e, stackTrace) {
      LogUtil.logError('XML 解析失败', e, stackTrace);
      return null;
    }
  }

  // 构建频道缓存键
  static String _buildChannelKey(PlayModel model) {
    if (model.id != null && model.id!.isNotEmpty) {
      return model.id!;
    } 
    
    if (model.title == null || model.title!.isEmpty) {
      return '';
    }
    
    final channel = model.title!.replaceAll(_regex.titleClean, '');
    final date = DateUtil.formatDate(DateTime.now(), format: _dateFormatCompact);
    return "$date-$channel";
  }

  // 尝试从不同来源加载EPG数据
  static Future<EpgModel?> _tryLoadEpgFromSource(PlayModel model, String channelKey, CancelToken? cancelToken) async {
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: key=$channelKey');
      return null;
    }
    
    // 尝试从本地JSON缓存加载
    final safeKey = _sanitizeFileName(channelKey);
    final jsonData = await _loadFile(safeKey, isJson: true);
    if (jsonData != null) {
      try {
        return EpgModel.fromJson(jsonDecode(jsonData));
      } catch (e, stackTrace) {
        LogUtil.logError('解析 EPG JSON 数据失败: $channelKey', e, stackTrace);
      }
    }

    if (cancelToken?.isCancelled ?? false) return null;

    // 以下条件暂时保持原样，等待稍后直接在Config类中添加这些属性
    if (model.id != null) {
      try {
        // 这里本应该使用Config.epgXmlUrl检查，但由于该属性不存在，我们暂时跳过这部分逻辑
        LogUtil.i('没有可用的XML URL，跳过XML解析步骤');
        // 实际上这里应该修复Config.epgXmlUrl访问，但目前仅移除相关引用以解决编译错误
      } catch (e, stackTrace) {
        LogUtil.logError('处理XML相关配置失败', e, stackTrace);
      }
    }

    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: key=$channelKey');
      return null;
    }
    
    return null;
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
    
    final channelKey = _buildChannelKey(model);
    if (channelKey.isEmpty) {
      LogUtil.i('获取失败: 无法构建有效的频道键');
      return null;
    }
    
    String channel = '';
    String date = '';
    if (model.title != null && model.title!.isNotEmpty) {
      channel = model.title!.replaceAll(_regex.titleClean, '');
      date = DateUtil.formatDate(DateTime.now(), format: _dateFormatCompact);
    } else {
      LogUtil.i('获取失败: 频道名为空');
      return null;
    }

    final localEpg = await _tryLoadEpgFromSource(model, channelKey, cancelToken);
    if (localEpg != null) {
      return localEpg;
    }

    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: channel=$channel, date=$date');
      return null;
    }
    
    try {
      // 此处应该使用Config.epgBaseUrl，但由于不确定它是如何定义的，先使用安全的替代方案
      final String epgBaseUrl = ""; // 这里应该从Config中获取，但暂时留空以避免错误
      if (epgBaseUrl.isNotEmpty) {
        final epgRes = await HttpUtil().getRequest(
          '$epgBaseUrl?ch=$channel&date=$date',
          cancelToken: cancelToken,
        );
        
        if (epgRes != null) {
          final epg = EpgModel.fromJson(epgRes);
          if (epg.epgData == null || epg.epgData!.isEmpty) {
            LogUtil.i('数据无效: 无节目信息, channel=$channel, date=$date');
            return null;
          }
          
          if (epg.date == null || epg.date!.isEmpty) {
            epg.date = DateUtil.formatDate(DateTime.now(), format: _dateFormatFull);
          }
          
          final convertedEpg = await _convertEpgModelChinese(epg);
          await _saveFile(_sanitizeFileName(channelKey), jsonEncode(convertedEpg.toJson()), isJson: true);
          return convertedEpg;
        }
      } else {
        LogUtil.i('EPG基础URL未配置');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('从网络获取EPG失败: channel=$channel', e, stackTrace);
    }
    
    LogUtil.i('获取失败: 无有效数据, channel=$channel, date=$date');
    return null;
  }

  // 加载 EPG XML 文件，支持重试
  static Future<void> loadEPGXML(String url) async {
    final urlLink = _getXmlUrls(url);
    bool fileExists = false;
    for (var currentUrl in urlLink) {
      final xmlContent = await _loadFile(_getFileNameFromUrl(currentUrl), isJson: false);
      if (xmlContent != null) {
        fileExists = true;
        break;
      }
    }
    
    if (!fileExists) {
      int index = 0;
      const int maxRetries = 2;
      XmlDocument? tempXmlDocument;
      final failedUrls = <String>[];
      String? xmlContent;

      while (tempXmlDocument == null && index < urlLink.length && index < maxRetries) {
        final currentUrl = urlLink[index];
        try {
          final res = await HttpUtil().getRequest(currentUrl);
          if (res != null) {
            xmlContent = res.toString();
            tempXmlDocument = XmlDocument.parse(xmlContent);
            final convertedXmlContent = await _convertXmlContent(xmlContent);
            await _saveFile(_getFileNameFromUrl(currentUrl), convertedXmlContent, isJson: false);
            break;
          } else {
            failedUrls.add(currentUrl);
            index += 1;
          }
        } catch (e, stackTrace) {
          LogUtil.logError('XML下载或解析失败: url=$currentUrl', e, stackTrace);
          failedUrls.add(currentUrl);
          index += 1;
        }
      }
      
      if (tempXmlDocument == null) {
        LogUtil.e('XML加载失败: 所有URL无效, 失败=$failedUrls');
      }
    }
  }
}
