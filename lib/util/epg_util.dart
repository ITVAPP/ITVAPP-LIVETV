import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
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

/// EPG 工具类，管理节目指南数据的获取、缓存和中文转换
class EpgUtil {
  EpgUtil._(); // 私有构造函数，防止实例化

  static Iterable<XmlElement>? _programmes; // 存储解析后的 XML 节目数据
  static const String _epgFolderName = 'epg_data'; // EPG数据文件夹名
  static Directory? _epgBaseDir; // EPG基础目录

  // 初始化EPG文件系统
  static Future<void> init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _epgBaseDir = Directory('${appDir.path}/$_epgFolderName');
      
      // 确保基础目录存在
      if (!await _epgBaseDir!.exists()) {
        await _epgBaseDir!.create(recursive: true);
      }
      
      // 清理旧数据
      await _cleanOldData();
      
      LogUtil.i('EPG文件系统初始化完成: ${_epgBaseDir!.path}');
    } catch (e, stackTrace) {
      LogUtil.logError('EPG文件系统初始化失败', e, stackTrace);
    }
  }
  
  // 清理旧数据（删除当前日期之前的文件夹）
  static Future<void> _cleanOldData() async {
    if (_epgBaseDir == null) return;
    
    try {
      final now = DateTime.now();
      final currentDate = DateUtil.formatDate(now, format: "yyyyMMdd");
      
      final List<FileSystemEntity> folders = await _epgBaseDir!.list().toList();
      for (var folder in folders) {
        if (folder is Directory) {
          final folderName = folder.path.split('/').last;
          // 如果能解析为日期且小于当前日期，则删除
          if (_isValidDateFolder(folderName) && folderName.compareTo(currentDate) < 0) {
            await folder.delete(recursive: true);
            LogUtil.i('删除过期EPG数据文件夹: $folderName');
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('清理EPG旧数据失败', e, stackTrace);
    }
  }
  
  // 判断是否为有效的日期文件夹名
  static bool _isValidDateFolder(String folderName) {
    // 检查是否为8位数字格式（yyyyMMdd）
    if (folderName.length != 8 || !RegExp(r'^\d{8}$').hasMatch(folderName)) {
      return false;
    }
    
    try {
      final year = int.parse(folderName.substring(0, 4));
      final month = int.parse(folderName.substring(4, 6));
      final day = int.parse(folderName.substring(6, 8));
      
      // 简单验证日期合法性
      if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // 获取今日EPG目录
  static Future<Directory> _getCurrentDateFolder() async {
    if (_epgBaseDir == null) await init();
    
    final currentDate = DateUtil.formatDate(DateTime.now(), format: "yyyyMMdd");
    final dateFolder = Directory('${_epgBaseDir!.path}/$currentDate');
    if (!await dateFolder.exists()) {
      await dateFolder.create(recursive: true);
    }
    return dateFolder;
  }
  
  // 保存EPG数据到文件
  static Future<void> _saveEpgToFile(String channelKey, EpgModel model) async {
    try {
      final dateFolder = await _getCurrentDateFolder();
      // 确保channelKey是文件名安全的
      final safeKey = channelKey.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final file = File('${dateFolder.path}/$safeKey.json');
      
      final jsonData = jsonEncode(model.toJson());
      await file.writeAsString(jsonData);
      
      LogUtil.i('EPG数据保存到文件: ${file.path}');
    } catch (e, stackTrace) {
      LogUtil.logError('保存EPG数据到文件失败: $channelKey', e, stackTrace);
    }
  }
  
  // 从文件加载EPG数据
  static Future<EpgModel?> _loadEpgFromFile(String channelKey) async {
    try {
      final dateFolder = await _getCurrentDateFolder();
      // 确保channelKey是文件名安全的
      final safeKey = channelKey.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final file = File('${dateFolder.path}/$safeKey.json');
      
      if (!await file.exists()) {
        return null;
      }
      
      final jsonData = await file.readAsString();
      final model = EpgModel.fromJson(jsonDecode(jsonData));
      
      LogUtil.i('从文件加载EPG数据: ${file.path}');
      return model;
    } catch (e, stackTrace) {
      LogUtil.logError('从文件加载EPG数据失败: $channelKey', e, stackTrace);
      return null;
    }
  }

  // 从缓存获取用户语言设置
  static Locale _getUserLocaleFromCache() {
    try {
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');
      // 返回有效语言代码或默认英语
      if (languageCode != null && languageCode.isNotEmpty) {
        return countryCode != null && countryCode.isNotEmpty
            ? Locale(languageCode, countryCode)
            : Locale(languageCode);
      }
      return const Locale('en');
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户语言设置失败', e, stackTrace);
      return const Locale('en'); // 错误时返回默认英语
    }
  }

  // 获取中文转换器，必要时返回 null
  static ZhConverter? _getChineseConverter() {
    final userLocale = _getUserLocaleFromCache();
    // 非中文语言无需转换
    if (!userLocale.languageCode.startsWith('zh')) {
      LogUtil.i('无需中文转换：用户语言非中文 (${userLocale.languageCode})');
      return null;
    }
    String userLang = userLocale.languageCode;
    if (userLocale.countryCode != null && userLocale.countryCode!.isNotEmpty) {
      userLang = '${userLocale.languageCode}_${userLocale.countryCode}';
    }
    // 根据语言区域选择转换方向
    if (userLang.contains('TW') || userLang.contains('HK') || userLang.contains('MO')) {
      LogUtil.i('需转换：简体转繁体 (语言=$userLang)');
      return ZhConverter('s2t');
    } else if (userLang.contains('CN') || userLang == 'zh') {
      LogUtil.i('需转换：繁体转简体 (语言=$userLang)');
      return ZhConverter('t2s');
    }
    LogUtil.i('无需中文转换：未识别中文变体 (语言=$userLang)');
    return null;
  }

  // 转换 EPG 数据中的中文标题和描述
  static EpgModel _convertEpgModelChinese(EpgModel model) {
    final converter = _getChineseConverter();
    if (converter == null) {
      return model; // 无需转换，直接返回
    }
    try {
      String? newChannelName = model.channelName;
      if (newChannelName != null && newChannelName.isNotEmpty) {
        newChannelName = converter.convert(newChannelName); // 转换频道名称
      }
      List<EpgData>? newEpgData;
      if (model.epgData != null && model.epgData!.isNotEmpty) {
        newEpgData = model.epgData!.map((epgData) {
          String? newTitle = epgData.title;
          String? newDesc = epgData.desc;
          if (newTitle != null && newTitle.isNotEmpty) {
            newTitle = converter.convert(newTitle); // 转换节目标题
          }
          if (newDesc != null && newDesc.isNotEmpty) {
            newDesc = converter.convert(newDesc); // 转换节目描述
          }
          return epgData.copyWith(title: newTitle, desc: newDesc);
        }).toList();
      }
      return model.copyWith(channelName: newChannelName, epgData: newEpgData);
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换失败，返回原数据', e, stackTrace);
      return model; // 转换失败，返回原数据
    }
  }

  // 获取 EPG 数据，支持缓存、XML 和网络请求
  static Future<EpgModel?> getEpg(PlayModel? model, {CancelToken? cancelToken}) async {
    if (model == null) {
      LogUtil.i('获取失败：输入模型为空');
      return null;
    }
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消：请求已取消');
      return null;
    }
    
    String channelKey = '';
    String channel = '';
    String date = '';
    final isHasXml = _programmes != null && _programmes!.isNotEmpty;

    if (model.id != null && model.id!.isNotEmpty && isHasXml) {
      channelKey = model.id!; // 使用频道 ID 作为缓存键
    } else {
      if (model.title == null || model.title!.isEmpty) {
        LogUtil.i('获取失败：频道标题为空');
        return null;
      }
      channel = model.title!.replaceAll(RegExp(r'[ -]'), ''); // 清理标题空格和连字符
      date = DateUtil.formatDate(DateTime.now(), format: "yyMMdd"); // 获取当前日期
      channelKey = "$date-$channel"; // 组合日期和频道名作为键
    }

    // 尝试从文件加载
    final cachedEpg = await _loadEpgFromFile(channelKey);
    if (cachedEpg != null) {
      LogUtil.i('从文件缓存获取：key=$channelKey');
      return cachedEpg;
    }

    // 从XML解析
    if (isHasXml) {
      EpgModel epgModel = EpgModel(
        channelName: model.title ?? '未知频道', 
        epgData: [],
        date: DateUtil.formatDate(DateTime.now(), format: "yyyy-MM-dd")
      );
      
      final matchedProgrammes = _programmes!.where((programme) => 
        programme.getAttribute('channel') == model.id);
        
      for (var programme in matchedProgrammes) {
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');
        if (start == null || stop == null) {
          LogUtil.i('解析失败：缺少 start 或 stop，channel=${model.id}');
          continue;
        }
        try {
          final dateStart = DateUtil.formatDate(
            DateUtil.parseCustomDateTimeString(start), 
            format: "HH:mm"
          );
          final dateEnd = DateUtil.formatDate(
            DateUtil.parseCustomDateTimeString(stop), 
            format: "HH:mm"
          );
          
          final timePattern = RegExp(r'^\d{2}:\d{2}$');
          if (!timePattern.hasMatch(dateStart) || !timePattern.hasMatch(dateEnd)) {
            LogUtil.i('时间格式无效：start=$dateStart, end=$dateEnd, channel=${model.id}');
            continue;
          }
          
          final titleElements = programme.findAllElements('title');
          if (titleElements.isEmpty) {
            LogUtil.i('解析失败：缺少标题，channel=${model.id}, start=$start');
            continue;
          }
          
          final title = titleElements.first.innerText;
          epgModel.epgData!.add(EpgData(title: title, start: dateStart, end: dateEnd));
        } catch (e) {
          LogUtil.e('解析失败：start=$start, stop=$stop, channel=${model.id}, 错误=$e');
          continue;
        }
      }
      
      if (epgModel.epgData!.isEmpty) {
        LogUtil.i('数据无效：无有效节目，channel=${model.id}');
        return null;
      }
      
      final convertedEpgModel = _convertEpgModelChinese(epgModel);
      await _saveEpgToFile(channelKey, convertedEpgModel);
      LogUtil.i('解析XML并保存：key=$channelKey');
      return convertedEpgModel;
    }

    // 从网络获取
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('获取取消：请求已取消，channel=$channel, date=$date');
      return null;
    }
    
    final epgRes = await HttpUtil().getRequest(
      '${Config.epgBaseUrl}?ch=$channel&date=$date', // 构造 EPG 请求 URL
      cancelToken: cancelToken,
    );
    
    if (epgRes != null) {
      final epg = EpgModel.fromJson(epgRes);
      if (epg.epgData == null || epg.epgData!.isEmpty) {
        LogUtil.i('数据无效：无节目信息，channel=$channel, date=$date');
        return null;
      }
      
      // 确保有日期字段
      if (epg.date == null || epg.date!.isEmpty) {
        epg.date = DateUtil.formatDate(DateTime.now(), format: "yyyy-MM-dd");
      }
      
      final convertedEpg = _convertEpgModelChinese(epg);
      await _saveEpgToFile(channelKey, convertedEpg);
      LogUtil.i('加载网络数据并保存：key=$channelKey');
      return convertedEpg;
    }
    
    LogUtil.i('获取失败：无有效数据，channel=$channel, date=$date');
    return null;
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
          tempXmlDocument = XmlDocument.parse(res.toString());
        } catch (e) {
          LogUtil.e('XML 解析失败：url=$currentUrl, 错误=$e');
          failedUrls.add(currentUrl);
          index += 1;
        }
      } else {
        LogUtil.i('XML 请求失败：url=$currentUrl');
        failedUrls.add(currentUrl);
        index += 1;
      }
    }
    if (tempXmlDocument == null) {
      LogUtil.e('XML 加载失败：所有 URL 无效，url=$url, 失败 URL=$failedUrls');
    }
    _programmes = tempXmlDocument?.findAllElements('programme');
  }

  // 重置 EPG XML 数据
  static void resetEPGXML() {
    _programmes = null; // 清空节目数据
  }
}
