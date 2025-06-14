import 'dart:io';
import 'dart:convert';
import 'dart:async';
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

/// 正则表达式常量类
class _RegExpConstants {
  final safeFileName = RegExp(r'[\\/:*?"<>|]'); /// 匹配文件名非法字符
  final dateValidation = RegExp(r'^\d{8}$'); /// 验证日期格式（yyyyMMdd）
  final titleClean = RegExp(r'[ -]'); /// 清理标题中的空格和连字符
  final timePattern = RegExp(r'^\d{2}:\d{2}$'); /// 验证时间格式（HH:mm）
}

/// EPG节目数据模型
class EpgData {
  String? desc; /// 节目描述
  String? end; /// 结束时间
  String? start; /// 开始时间
  String? title; /// 节目标题

  EpgData({this.desc, this.end, this.start, this.title});

  /// 从JSON构造EPG数据，验证并解析时间格式
  EpgData.fromJson(dynamic json) {
    desc = json['desc'] == '' ? null : json['desc'] as String?; /// 解析节目描述，空值设为null
    start = json['start'] as String?; /// 解析开始时间
    end = json['end'] as String?; /// 解析结束时间
    title = json['title'] as String?; /// 解析节目标题
    if (start != null && end != null) {
      if (!EpgUtil._regex.timePattern.hasMatch(start!) || !EpgUtil._regex.timePattern.hasMatch(end!)) {
        LogUtil.i('无效时间格式: start=$start, end=$end');
        start = null;
        end = null;
      }
    }
  }

  /// 复制数据并更新指定字段
  EpgData copyWith({String? desc, String? end, String? start, String? title}) =>
      EpgData(
        desc: desc ?? this.desc,
        end: end ?? this.end,
        start: start ?? this.start,
        title: title ?? this.title,
      );

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['desc'] = desc;
    map['end'] = end;
    map['start'] = start;
    map['title'] = title;
    return map;
  }
}

/// EPG数据模型，包含频道和节目信息
class EpgModel {
  String? channelName; /// 频道名称
  String? date; /// 日期
  List<EpgData>? epgData; /// 节目数据列表

  EpgModel({this.channelName, this.date, this.epgData});

  /// 从JSON构造EPG模型，过滤无效数据
  EpgModel.fromJson(dynamic json) {
    channelName = json['channel_name'] as String?;
    date = json['date'] as String?;
    if (json['epg_data'] != null) {
      epgData = [];
      for (var v in json['epg_data']) {
        final epgDataItem = EpgData.fromJson(v);
        if (epgDataItem.title == null || epgDataItem.start == null || epgDataItem.end == null) {
          LogUtil.i('无效节目数据: 缺少必要字段=$v');
          continue;
        }
        epgData!.add(epgDataItem);
      }
    }
    if (epgData == null || epgData!.isEmpty) {
      LogUtil.i('解析失败: 无有效节目, channel=$channelName, date=$date');
    }
    LogUtil.i('解析EPG模型: channel=$channelName, date=$date, count=${epgData?.length ?? 0}');
  }

  /// 复制模型并更新指定字段
  EpgModel copyWith({String? channelName, String? date, List<EpgData>? epgData}) =>
      EpgModel(
        channelName: channelName ?? this.channelName,
        date: date ?? this.date,
        epgData: epgData ?? this.epgData,
      );

  /// 转换为JSON格式
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

/// EPG工具类，管理节目指南数据的获取、缓存和中文转换
class EpgUtil {
  EpgUtil._(); /// 私有构造函数，防止实例化

  static final _RegExpConstants _regex = _RegExpConstants(); /// 正则表达式常量
  static const String _epgFolderName = 'epg_data'; /// EPG数据存储文件夹
  static Directory? _epgBaseDir; /// EPG数据基础目录
  static ZhConverter? _zhConverter; /// 中文转换器实例
  static String? _currentDateString; /// 当前日期字符串
  static Directory? _currentDateFolder; /// 当前日期文件夹
  static Locale? _cachedUserLocale; /// 用户语言设置缓存
  static String? _cachedConversionType; /// 中文转换类型缓存
  static const String _dateFormatYMD = "yyyyMMdd"; /// 年月日格式
  static const String _dateFormatHM = "HH:mm"; /// 时分格式
  static const String _dateFormatFull = "yyyy-MM-dd"; /// 完整日期格式
  static const String _dateFormatCompact = "yyMMdd"; /// 紧凑日期格式
  static const Locale _defaultLocale = Locale('zh', 'CN'); /// 默认区域设置
  
  // 性能优化：添加初始化锁和内存缓存
  static final Completer<void> _initCompleter = Completer<void>();
  static bool _isInitializing = false;
  static final Map<String, String> _fileContentCache = {}; /// 文件内容缓存
  static final Map<String, Completer<String?>> _downloadingUrls = {}; /// 正在下载的URL
  
  /// 获取当前日期字符串（yyyyMMdd）
  static String get _currentDate => _currentDateString ?? DateUtil.formatDate(DateTime.now(), format: _dateFormatYMD);

  /// 初始化EPG文件系统，创建目录并清理过期数据
  static Future<void> init() async {
    if (_epgBaseDir != null) return; /// 已初始化，直接返回
    
    if (_isInitializing) {
      await _initCompleter.future; /// 等待正在进行的初始化
      return;
    }
    
    _isInitializing = true;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _epgBaseDir = Directory('${appDir.path}/$_epgFolderName');
      
      if (!await _epgBaseDir!.exists()) {
        await _epgBaseDir!.create(recursive: true); /// 创建EPG目录
      }
      
      _currentDateString = DateUtil.formatDate(DateTime.now(), format: _dateFormatYMD);
      _currentDateFolder = Directory('${_epgBaseDir!.path}/$_currentDateString');
      if (!await _currentDateFolder!.exists()) {
        await _currentDateFolder!.create(recursive: true); /// 创建当前日期文件夹
      }
      
      await _cleanOldData(); /// 清理过期数据
      
      if (Config.epgXmlUrl.isNotEmpty) {
        Future(() async {
          try {
            await loadEPGXML(Config.epgXmlUrl);
            LogUtil.i('EPG XML后台下载完成');
          } catch (e, stackTrace) {
            LogUtil.logError('后台下载EPG XML失败', e, stackTrace);
          }
        });
      }
      
      LogUtil.i('EPG文件系统初始化完成: ${_epgBaseDir!.path}');
      
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('EPG文件系统初始化失败', e, stackTrace);
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e);
      }
      rethrow;
    }
  }
  
  /// 清理过期数据，删除当前日期前的文件夹
  static Future<void> _cleanOldData() async {
    if (_epgBaseDir == null) return;
    
    try {
      final folders = await _epgBaseDir!.list().toList();
      final deleteTasks = <Future>[];
      
      for (var folder in folders) {
        if (folder is Directory) {
          final folderName = folder.path.split('/').last;
          if (_isValidDateFolder(folderName) && folderName.compareTo(_currentDate) < 0) {
            deleteTasks.add(folder.delete(recursive: true).then((_) {
              LogUtil.i('删除过期EPG数据: $folderName');
            }));
          }
        }
      }
      
      if (deleteTasks.isNotEmpty) {
        await Future.wait(deleteTasks);
      }
      
      _fileContentCache.clear(); /// 清理内存缓存
    } catch (e, stackTrace) {
      LogUtil.logError('清理EPG旧数据失败', e, stackTrace);
    }
  }
  
  /// 验证日期文件夹名格式（yyyyMMdd）
  static bool _isValidDateFolder(String folderName) {
    if (folderName.length != 8 || !_regex.dateValidation.hasMatch(folderName)) {
      return false;
    }
    
    try {
      final year = int.parse(folderName.substring(0, 4));
      final month = int.parse(folderName.substring(4, 6));
      final day = int.parse(folderName.substring(6, 8));
      
      return year >= 2000 && year <= 2100 && 
             month >= 1 && month <= 12 && 
             day >= 1 && day <= 31;
    } catch (e) {
      return false; /// 日期解析失败
    }
  }
  
  /// 获取当前日期的EPG目录
  static Future<Directory> _getCurrentDateFolder() async {
    if (_epgBaseDir == null) await init();
    return _currentDateFolder!;
  }
  
  /// 清理文件名中的非法字符
  static String _sanitizeFileName(String filename) {
    return filename.replaceAll(_regex.safeFileName, '_');
  }
  
  /// 从URL提取文件名
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
  
  /// 获取文件完整路径
  static Future<String> _getFilePath(String fileName, {bool isJson = true}) async {
    if (_currentDateFolder == null) {
      await init();
    }
    return '${_currentDateFolder!.path}/$fileName${isJson ? '.json' : '.xml'}';
  }
  
  /// 保存文件内容到磁盘并更新缓存
  static Future<void> _saveFile(String fileName, String content, {bool isJson = true}) async {
    try {
      final filePath = await _getFilePath(fileName, isJson: isJson);
      await File(filePath).writeAsString(content, flush: true);
      
      final cacheKey = '$fileName${isJson ? '.json' : '.xml'}';
      _fileContentCache[cacheKey] = content; /// 更新内存缓存
    } catch (e, stackTrace) {
      LogUtil.logError('保存${isJson ? 'EPG' : 'XML'}数据失败: $fileName', e, stackTrace);
    }
  }
  
  /// 加载文件内容，优先从内存缓存获取
  static Future<String?> _loadFile(String fileName, {bool isJson = true}) async {
    try {
      final cacheKey = '$fileName${isJson ? '.json' : '.xml'}';
      if (_fileContentCache.containsKey(cacheKey)) {
        return _fileContentCache[cacheKey]; /// 返回缓存内容
      }
      
      final filePath = await _getFilePath(fileName, isJson: isJson);
      final file = File(filePath);
      if (!await file.exists()) {
        return null; /// 文件不存在
      }
      
      final content = await file.readAsString();
      if (content.isEmpty) {
        return null; /// 文件内容为空
      }
      
      _fileContentCache[cacheKey] = content; /// 更新内存缓存
      
      return content;
    } catch (e, stackTrace) {
      LogUtil.logError('加载${isJson ? 'EPG' : 'XML'}数据失败: $fileName', e, stackTrace);
      return null;
    }
  }
  
  /// 获取XML URL列表
  static List<String> _getXmlUrls(String url) {
    final uStr = url.replaceAll('/h', ',h');
    return uStr.split(',');
  }

  /// 获取缓存的用户语言设置
  static Locale _getUserLocaleFromCache() {
    if (_cachedUserLocale != null) {
      return _cachedUserLocale!;
    }
    
    try {
      String? languageCode = SpUtil.getString('languageCode');
      if (languageCode == null || languageCode.isEmpty) {
        _cachedUserLocale = _defaultLocale;
        return _defaultLocale;
      }
      
      String? countryCode = SpUtil.getString('countryCode');
      _cachedUserLocale = countryCode != null && countryCode.isNotEmpty
          ? Locale(languageCode, countryCode)
          : Locale(languageCode);
      return _cachedUserLocale!;
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户语言失败', e, stackTrace);
      _cachedUserLocale = _defaultLocale;
      return _defaultLocale;
    }
  }

  /// 刷新语言缓存
  static void refreshLanguageCache() {
    _cachedUserLocale = null;
    _cachedConversionType = null;
    _zhConverter = null;
  }

  /// 获取中文转换器实例
  static Future<ZhConverter?> _getChineseConverter() async {
    if (_cachedConversionType != null) {
      if (_cachedConversionType!.isEmpty) {
        return null;
      }
      if (_zhConverter == null || _zhConverter!.conversionType != _cachedConversionType) {
        _zhConverter = ZhConverter(_cachedConversionType!);
        await _zhConverter!.initialize();
      }
      return _zhConverter;
    }

    final userLocale = _getUserLocaleFromCache();
    final languageCode = userLocale.languageCode;
    if (languageCode != 'zh' && !languageCode.startsWith('zh_')) {
      _cachedConversionType = '';
      return null;
    }

    String userLang = languageCode;
    if (userLocale.countryCode != null && userLocale.countryCode!.isNotEmpty) {
      userLang = '${languageCode}_${userLocale.countryCode}';
    }

    _cachedConversionType = userLang.contains('TW') || userLang.contains('HK') || userLang.contains('MO')
        ? 's2t'
        : userLang.contains('CN') || userLang == 'zh'
            ? 't2s'
            : '';
    
    if (_cachedConversionType!.isEmpty) {
      LogUtil.i('无需中文转换: 未识别变体($userLang)');
      return null;
    }

    _zhConverter = ZhConverter(_cachedConversionType!);
    await _zhConverter!.initialize();
    return _zhConverter;
  }

  /// 批量转换中文字符串
  static Future<List<String?>> _convertChineseStringBatch(List<String?> texts, ZhConverter converter) async {
    final results = <String?>[];
    for (var text in texts) {
      if (text == null || text.isEmpty) {
        results.add(text);
      } else {
        try {
          results.add(await converter.convert(text));
        } catch (e) {
          LogUtil.e('中文转换失败: $text, 错误=$e');
          results.add(text);
        }
      }
    }
    return results;
  }

  /// 转换单个中文字符串
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

  /// 转换XML内容中的中文文本
  static Future<String> _convertXmlContent(String xmlContent) async {
    final converter = await _getChineseConverter();
    if (converter == null) {
      return xmlContent; /// 无需转换，直接返回
    }
    
    try {
      final document = XmlDocument.parse(xmlContent);
      final tagsToConvert = ['title', 'desc', 'subtitle', 'category', 'display-name'];
      
      final elementsToConvert = <XmlElement>[];
      final textsToConvert = <String>[];
      
      for (var element in document.descendants.whereType<XmlElement>()) {
        if (tagsToConvert.contains(element.name.local) && element.innerText.isNotEmpty) {
          elementsToConvert.add(element);
          textsToConvert.add(element.innerText);
        }
      }
      
      if (elementsToConvert.isEmpty) {
        return xmlContent; /// 无需转换的元素
      }
      
      final convertedTexts = await _convertChineseStringBatch(textsToConvert, converter);
      
      for (var i = 0; i < elementsToConvert.length; i++) {
        if (convertedTexts[i] != null && convertedTexts[i] != textsToConvert[i]) {
          elementsToConvert[i].innerText = convertedTexts[i]!;
        }
      }
      
      return document.toXmlString();
    } catch (e, stackTrace) {
      LogUtil.logError('XML中文转换失败', e, stackTrace);
      return xmlContent;
    }
  }

  /// 转换EPG数据中的中文内容
  static Future<EpgModel> _convertEpgModelChinese(EpgModel model) async {
    final converter = await _getChineseConverter();
    if (converter == null || (model.channelName == null && model.epgData == null)) {
      return model; /// 无需转换，直接返回
    }

    final textsToConvert = <String?>[];
    textsToConvert.add(model.channelName);
    
    if (model.epgData != null) {
      for (var epg in model.epgData!) {
        textsToConvert.add(epg.title);
        textsToConvert.add(epg.desc);
      }
    }
    
    final convertedTexts = await _convertChineseStringBatch(textsToConvert, converter);
    
    var index = 0;
    final newChannelName = convertedTexts[index++] ?? model.channelName;
    
    List<EpgData>? newEpgData;
    if (model.epgData != null) {
      newEpgData = [];
      for (var epg in model.epgData!) {
        newEpgData.add(epg.copyWith(
          title: convertedTexts[index++] ?? epg.title,
          desc: convertedTexts[index++] ?? epg.desc,
        ));
      }
    }

    return model.copyWith(
      channelName: newChannelName,
      epgData: newEpgData,
    );
  }

  /// 解析节目开始和结束时间
  static Future<Map<String, String>?> _parseStartEndTimes(String? start, String? stop) async {
    if (start == null || stop == null) {
      return null; /// 时间为空，返回null
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
        return null; /// 时间格式无效
      }
      
      return {'start': dateStart, 'end': dateEnd};
    } catch (e) {
      LogUtil.e('时间解析失败: start=$start, stop=$stop, 错误=$e');
      return null;
    }
  }

  /// 从XML字符串解析EPG数据
  static Future<EpgModel?> _parseXmlFromString(String xmlString, PlayModel model) async {
    if (model.id == null) {
      LogUtil.i('解析失败: 频道ID为空');
      return null;
    }
    
    try {
      final xmlDocument = XmlDocument.parse(xmlString);
      
      final epgModel = EpgModel(
        channelName: model.title ?? '未知频道', 
        epgData: [],
        date: DateUtil.formatDate(DateTime.now(), format: _dateFormatFull),
      );
      
      for (var programme in xmlDocument.findAllElements('programme')) {
        if (programme.getAttribute('channel') != model.id) {
          continue;
        }
        
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');
        
        final times = await _parseStartEndTimes(start, stop);
        if (times == null) {
          LogUtil.i('无效时间: channel=${model.id}, start=$start, stop=$stop');
          continue;
        }
        
        String? title;
        String? desc;
        
        for (var child in programme.children) {
          if (child is XmlElement) {
            if (child.name.local == 'title' && title == null) {
              title = child.innerText;
            } else if (child.name.local == 'desc' && desc == null) {
              desc = child.innerText;
            }
          }
        }
        
        if (title == null || title.isEmpty) {
          LogUtil.i('缺少标题: channel=${model.id}, start=$start');
          continue;
        }
        
        epgModel.epgData!.add(EpgData(
          title: title, 
          start: times['start'], 
          end: times['end'],
          desc: desc
        ));
      }
      
      if (epgModel.epgData!.isEmpty) {
        LogUtil.i('无有效节目: channel=${model.id}');
        return null;
      }
      
      return epgModel;
    } catch (e, stackTrace) {
      LogUtil.logError('XML解析失败', e, stackTrace);
      return null;
    }
  }

  /// 构建频道缓存键
  static String _buildChannelKey(PlayModel model) {
    if (model.id != null && model.id!.isNotEmpty) {
      return model.id!;
    } 
    
    if (model.title == null || model.title!.isEmpty) {
      return '';
    }
    
    final channel = model.title!.replaceAll(_regex.titleClean, '');
    final date = DateUtil.formatDate(DateTime.now(), format: _dateFormatCompact);
    final buffer = StringBuffer()
      ..write(date)
      ..write('-')
      ..write(channel);
    return buffer.toString();
  }

  /// 从不同来源加载EPG数据
  static Future<EpgModel?> _tryLoadEpgFromSource(PlayModel model, String channelKey, CancelToken? cancelToken) async {
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消: key=$channelKey');
      return null;
    }
    
    final safeKey = _sanitizeFileName(channelKey);
    final jsonData = await _loadFile(safeKey, isJson: true);
    if (jsonData != null) {
      try {
        return EpgModel.fromJson(jsonDecode(jsonData));
      } catch (e, stackTrace) {
        LogUtil.logError('解析EPG JSON失败: $channelKey', e, stackTrace);
      }
    }

    if (cancelToken?.isCancelled ?? false) return null; /// 获取取消，直接返回

    if (Config.epgXmlUrl.isNotEmpty && model.id != null) {
      try {
        final urlLink = _getXmlUrls(Config.epgXmlUrl);
        String? xmlContent;
        for (var currentUrl in urlLink) {
          xmlContent = await _loadFile(_getFileNameFromUrl(currentUrl), isJson: false);
          if (xmlContent != null) {
            break;
          }
        }
        
        if (xmlContent == null) {
          LogUtil.i('本地无XML，尝试下载: ${Config.epgXmlUrl}');
          await loadEPGXML(Config.epgXmlUrl);
          
          for (var currentUrl in urlLink) {
            xmlContent = await _loadFile(_getFileNameFromUrl(currentUrl), isJson: false);
            if (xmlContent != null) {
              break;
            }
          }
        }
        
        if (xmlContent != null) {
          final epgModel = await _parseXmlFromString(xmlContent, model);
          if (epgModel != null) {
            final convertedEpgModel = await _convertEpgModelChinese(epgModel);
            await _saveFile(safeKey, jsonEncode(convertedEpgModel.toJson()), isJson: true);
            return convertedEpgModel;
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('本地XML解析失败', e, stackTrace);
      }
    }

    if (cancelToken?.isCancelled ?? false) return null; /// 获取取消，直接返回
    
    return null;
  }

  /// 获取EPG数据，优先从缓存、XML或网络加载
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
      LogUtil.i('获取失败: 无效频道键');
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
      final epgRes = await HttpUtil().getRequest(
        '${Config.epgBaseUrl}?ch=$channel&date=$date',
        cancelToken: cancelToken,
      );
      
      if (epgRes != null) {
        final epg = EpgModel.fromJson(epgRes);
        if (epg.epgData == null || epg.epgData!.isEmpty) {
          LogUtil.i('无节目信息: channel=$channel, date=$date');
          return null;
        }
        
        if (epg.date == null || epg.date!.isEmpty) {
          epg.date = DateUtil.formatDate(DateTime.now(), format: _dateFormatFull);
        }
        
        final convertedEpg = await _convertEpgModelChinese(epg);
        await _saveFile(_sanitizeFileName(channelKey), jsonEncode(convertedEpg.toJson()), isJson: true);
        return convertedEpg;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('网络获取EPG失败: channel=$channel', e, stackTrace);
    }
    
    LogUtil.i('获取失败: 无有效数据, channel=$channel, date=$date');
    return null;
  }

  /// 加载EPG XML文件，支持并发下载
  static Future<void> loadEPGXML(String url) async {
    LogUtil.i('开始加载EPG XML: $url');
    
    final urlLink = _getXmlUrls(url);
    
    for (var currentUrl in urlLink) {
      final fileName = _getFileNameFromUrl(currentUrl);
      final xmlContent = await _loadFile(fileName, isJson: false);
      if (xmlContent != null) {
        LogUtil.i('使用本地缓存: $fileName');
        return;
      }
    }
    
    final downloadTasks = <Future<void>>[];
    final successCompleter = Completer<void>();
    var hasSucceeded = false;
    
    for (var currentUrl in urlLink) {
      if (_downloadingUrls.containsKey(currentUrl)) {
        downloadTasks.add(_downloadingUrls[currentUrl]!.future.then((_) {}));
        continue;
      }
      
      final urlCompleter = Completer<String?>();
      _downloadingUrls[currentUrl] = urlCompleter;
      
      final task = Future(() async {
        try {
          if (hasSucceeded || successCompleter.isCompleted) {
            urlCompleter.complete(null);
            return;
          }
          
          final xmlContent = await HttpUtil().getRequest<String>(
            currentUrl,
            options: Options(
              extra: {
                'connectTimeout': const Duration(seconds: 5),
                'receiveTimeout': const Duration(seconds: 168),
              },
            ),
            retryCount: 2,
          );
          
          if (xmlContent != null && xmlContent.isNotEmpty && !hasSucceeded) {
            final xmlDocument = XmlDocument.parse(xmlContent);
            
            final channels = xmlDocument.findAllElements('channel').length;
            final programmes = xmlDocument.findAllElements('programme').length;
            LogUtil.i('XML解析成功: 频道=$channels, 节目=$programmes');
            
            final convertedXmlContent = await _convertXmlContent(xmlContent);
            await _saveFile(_getFileNameFromUrl(currentUrl), convertedXmlContent, isJson: false);
            
            LogUtil.i('EPG XML加载成功: $currentUrl');
            
            hasSucceeded = true;
            if (!successCompleter.isCompleted) {
              successCompleter.complete();
            }
            urlCompleter.complete(convertedXmlContent);
          } else {
            urlCompleter.complete(null);
          }
        } catch (e, stackTrace) {
          LogUtil.logError('XML下载失败: $currentUrl', e, stackTrace);
          urlCompleter.complete(null);
        } finally {
          _downloadingUrls.remove(currentUrl);
        }
      });
      
      downloadTasks.add(task);
    }
    
    try {
      await Future.any([
        successCompleter.future,
        Future.wait(downloadTasks).then((_) {
          if (!hasSucceeded) {
            throw Exception('所有URL下载失败');
          }
        }),
      ]);
    } catch (e) {
      LogUtil.e('EPG XML加载失败: 所有URL不可用');
    }
  }
}
