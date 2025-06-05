import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// Bing 图片工具类，管理图片的下载、缓存和清理
class BingUtil {
  static List<String> bingImgUrls = []; // 存储所有 Bing 图片本地路径
  static String? bingImgUrl; // 存储单张 Bing 图片本地路径
  static const int _maxRetries = 2; // 最大重试次数
  static const int _maxImages = 8; // 最大图片数量
  static const int _deleteRetries = 2; // 删除文件最大重试次数
  static const Duration _retryDelay = Duration(milliseconds: 500); // 重试延迟
  static const int _maxConcurrentDeletes = 2; // 最大并发删除任务数
  static const int _maxConcurrentDownloads = 2; // 最大并发下载任务数
  static const String _imageExtension = '.jpg'; // 图片文件扩展名

  static String? _cachedLocalStoragePath; // 缓存基础存储路径
  static String? _cachedCurrentDateFolder; // 缓存当前日期文件夹路径
  static List<String>? _cachedTodayImages; // 缓存当天图片列表
  static List<String>? _cachedAllImages; // 缓存所有图片列表
  
  // 日期格式正则表达式，验证 yyyyMMdd
  static final RegExp _dateRegExp = RegExp(r'^\d{8}$');

  // 获取本地存储基础路径
  static Future<String> _getLocalStoragePath() async {
    if (_cachedLocalStoragePath != null) return _cachedLocalStoragePath!;
    final directory = await getApplicationDocumentsDirectory();
    final bingDir = Directory('${directory.path}/pic');
    if (!await bingDir.exists()) {
      await bingDir.create(recursive: true); // 创建图片存储目录
    }
    _cachedLocalStoragePath = bingDir.path;
    return _cachedLocalStoragePath!;
  }

  // 获取当前日期文件夹路径
  static Future<String> _getCurrentDateFolder() async {
    if (_cachedCurrentDateFolder != null) return _cachedCurrentDateFolder!;
    
    final basePath = await _getLocalStoragePath();
    final dateStr = _getCurrentDateString();
    final dateFolder = Directory('$basePath/$dateStr');
    if (!await dateFolder.exists()) {
      await dateFolder.create(recursive: true); // 创建日期目录
    }
    _cachedCurrentDateFolder = dateFolder.path;
    return _cachedCurrentDateFolder!;
  }

  // 获取当前日期字符串（yyyyMMdd）
  static String _getCurrentDateString() {
    // 返回格式化日期字符串
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  // 验证文件夹名是否为有效日期格式
  static bool _isValidDateFolder(String folderName) {
    // 校验文件夹名是否为 yyyyMMdd 格式
    if (folderName.length != 8 || !_dateRegExp.hasMatch(folderName)) return false;
    
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

  // 生成格式化文件名
  static String _generateFileName(int index) {
    // 返回格式化序号文件名
    return (index + 1).toString().padLeft(2, '0');
  }

  // 清理内存缓存
  static void _clearMemoryCache({bool keepDateFolder = false}) {
    // 清除图片列表缓存，保留日期文件夹缓存（可选）
    _cachedTodayImages = null;
    _cachedAllImages = null;
    if (!keepDateFolder) {
      _cachedCurrentDateFolder = null;
    }
  }

  // 过滤图片文件
  static List<String> _filterImageFiles(List<FileSystemEntity> files) {
    // 返回排序后的图片文件路径列表
    return files
        .where((file) => file is File && file.path.endsWith(_imageExtension))
        .map((file) => file.path)
        .toList()
      ..sort();
  }

  // 获取当天本地图片列表
  static Future<List<String>> _getLocalImagesForToday() async {
    if (_cachedTodayImages != null) {
      return _cachedTodayImages!; // 返回缓存的当天图片列表
    }
    
    final todayFolder = await _getCurrentDateFolder();
    final dir = Directory(todayFolder);
    if (!await dir.exists()) return [];
    
    final files = await dir.list().toList();
    _cachedTodayImages = _filterImageFiles(files);
    
    LogUtil.i('加载当天图片: ${_cachedTodayImages!.length} 张');
    return _cachedTodayImages!;
  }

  // 获取所有本地图片列表
  static Future<List<String>> _getAllLocalImages() async {
    if (_cachedAllImages != null) {
      return _cachedAllImages!; // 返回缓存的所有图片列表
    }
    
    final basePath = await _getLocalStoragePath();
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) return [];
    
    final List<String> allImages = [];
    final folders = await baseDir.list().where((entity) => entity is Directory).toList();
    
    // 批量处理文件夹
    final folderTasks = personally((folder) async {
      if (folder is Directory) {
        final files = await folder.list().toList();
        return _filterImageFiles(files);
      }
      return <String>[];
    });
    
    final results = await Future.wait(folderTasks);
    for (final images in results) {
      allImages.addAll(images);
    }
    
    allImages.sort();
    _cachedAllImages = allImages;
    LogUtil.i('加载所有图片: ${allImages.length} 张');
    return allImages;
  }

  // 删除文件夹，支持重试
  static Future<void> _deleteFolderWithRetry(Directory folder) async {
    for (int retry = 0; retry < _deleteRetries; retry++) {
      try {
        await folder.delete(recursive: true); // 删除文件夹及内容
        LogUtil.i('删除文件夹: ${folder.path}');
        break;
      } catch (e) {
        if (retry == _deleteRetries - 1) {
          LogUtil.logError('删除文件夹失败: ${folder.path}', e);
        } else {
          await Future.delayed(_retryDelay); // 等待重试
        }
      }
    }
  }

  // 删除非当天的旧图片文件夹
  static Future<void> _deleteOldImages() async {
    try {
      final basePath = await _getLocalStoragePath();
      final baseDir = Directory(basePath);
      if (!await baseDir.exists()) return;
      
      final currentDateStr = _getCurrentDateString();
      final entities = await baseDir.list().toList();
      
      // 过滤需要删除的文件夹
      final foldersToDelete = entities
          .whereType<Directory>()
          .where((folder) {
            final folderName = folder.path.split('/').last;
            return _isValidDateFolder(folderName) && folderName != currentDateStr;
          })
          .toList();
      
      if (foldersToDelete.isEmpty) {
        LogUtil.i('无旧图片文件夹需清理');
        return;
      }
      
      // 分批并发删除
      for (int i = 0; i < foldersToDelete.length; i += _maxConcurrentDeletes) {
        final batch = foldersToDelete.sublist(
          i, 
          (i + _maxConcurrentDeletes).clamp(0, foldersToDelete.length)
        );
        await Future.wait(batch.map(_deleteFolderWithRetry));
      }
      
      _clearMemoryCache(keepDateFolder: true); // 保留日期文件夹缓存
      LogUtil.i('清理旧图片文件夹: ${foldersToDelete.length} 个');
    } catch (e, stackTrace) {
      LogUtil.logError('清理旧图片文件夹失败', e, stackTrace);
    }
  }

  // 下载并保存图片到本地
  static Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final dirPath = await _getCurrentDateFolder();
      final filePath = '$dirPath/$fileName$_imageExtension';
      LogUtil.i('下载图片: $url 到 $filePath');

      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response?.statusCode == 200 && response?.data is List<int>) {
        final file = File(filePath);
        await file.writeAsBytes(response!.data as List<int>);
        LogUtil.i('图片保存成功: $filePath');
        _clearMemoryCache(keepDateFolder: true);
        return filePath;
      }
      LogUtil.e('下载失败: 状态码=${response?.statusCode}');
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('下载图片失败: $url', e, stackTrace);
      return null;
    }
  }

  // 回退到本地已有图片
  static Future<List<String>> _fallbackToLocalImages() async {
    // 返回本地图片列表或空列表
    final allLocalImages = await _getAllLocalImages();
    if (allLocalImages.isNotEmpty) {
      bingImgUrls = allLocalImages;
      LogUtil.i('回退到本地图片');
      return bingImgUrls;
    }
    LogUtil.e('无本地图片可用');
    return [];
  }

  // 获取 Bing 图片 URL，支持重试
  static Future<String?> _fetchBingImageUrlWithRetry(int idx, [int retryCount = 0, String? channelId]) async {
    try {
      final baseUrl = 'https://bing.biturl.top/?resolution=1366&format=json&index=$idx';
      final url = channelId != null ? '$baseUrl&channelId=$channelId' : baseUrl;
      
      final res = await HttpUtil().getRequest(url);
      final imageUrl = res?['url']?.isNotEmpty ?? false ? res['url'] : null;

      if (imageUrl != null && Uri.tryParse(imageUrl)?.hasAbsolutePath == true) {
        return imageUrl; // 返回有效图片 URL
      }
      throw Exception('无效图片 URL: $imageUrl');
    } catch (e) {
      if (retryCount < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 200 * (retryCount + 1)));
        return _fetchBingImageUrlWithRetry(idx, retryCount + 1, channelId); // 重试
      }
      LogUtil.logError('获取第 $idx 张图片 URL 失败', e);
      return null;
    }
  }

  // 获取多张 Bing 图片并下载
  static Future<List<String>> getBingImgUrls({String? channelId}) async {
    try {
      List<String> localImages = await _getLocalImagesForToday();
      if (localImages.length == _maxImages) {
        bingImgUrls = localImages;
        return bingImgUrls; // 返回当天缓存图片
      }

      // 创建下载任务
      final downloadTasks = List.generate(_maxImages, (index) async {
        final url = await _fetchBingImageUrlWithRetry(index, 0, channelId);
        if (url != null) {
          final fileName = _generateFileName(index);
          return await _downloadAndSaveImage(url, fileName);
        }
        return null;
      });

      // 分批执行下载
      final List<String> paths = [];
      for (int i = 0; i < downloadTasks.length; i += _maxConcurrentDownloads) {
        final batch = downloadTasks.sublist(
          i, 
          (i + _maxConcurrentDownloads).clamp(0, downloadTasks.length)
        );
        final results = await Future.wait(batch);
        paths.addAll(results.where((path) => path != null).cast<String>());
      }

      if (paths.isNotEmpty) {
        await _deleteOldImages();
        bingImgUrls = paths;
        LogUtil.i('下载图片成功: ${paths.length} 张');
      } else {
        return await _fallbackToLocalImages();
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片失败', e, stackTrace);
      return await _fallbackToLocalImages();
    }
  }

  // 获取单张 Bing 图片，优先使用缓存
  static Future<String?> getBingImgUrl({String? channelId}) async {
    try {
      final localImages = await _getLocalImagesForToday();
      if (localImages.isNotEmpty) {
        bingImgUrl = localImages.first;
        return bingImgUrl; // 返回当天缓存单张图片
      }

      final url = await _fetchBingImageUrlWithRetry(0, 0, channelId);
      if (url != null) {
        final fileName = _generateFileName(0);
        bingImgUrl = await _downloadAndSaveImage(url, fileName);
        if (bingImgUrl != null) {
          await _deleteOldImages(); // 清理旧图片
        }
        return bingImgUrl;
      }

      final allLocalImages = await _getAllLocalImages();
      if (allLocalImages.isNotEmpty) {
        bingImgUrl = allLocalImages.first;
        LogUtil.i('回退到本地单张图片');
        return bingImgUrl;
      }

      LogUtil.e('无可用图片');
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取单张 Bing 图片失败', e, stackTrace);
      final allLocalImages = await _getAllLocalImages();
      if (allLocalImages.isNotEmpty) {
        bingImgUrl = allLocalImages.first;
        return bingImgUrl;
      }
      return null;
    }
  }

  // 清除所有缓存和本地图片
  static Future<void> clearCache() async {
    try {
      bingImgUrls = [];
      bingImgUrl = null;
      _cachedLocalStoragePath = null;
      _clearMemoryCache();
      
      final dirPath = await _getLocalStoragePath();
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true); // 删除图片目录
        await dir.create(); // 重新创建空目录
        LogUtil.i('清除所有 Bing 图片缓存');
      }
    } catch (e) {
      LogUtil.logError('清除缓存失败', e);
    }
  }
}
