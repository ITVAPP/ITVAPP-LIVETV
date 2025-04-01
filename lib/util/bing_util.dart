import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class BingUtil {
  static List<String> bingImgUrls = []; // 存储所有 Bing 图片的本地路径
  static String? bingImgUrl; // 存储单张 Bing 图片的本地路径
  static const int _maxRetries = 2; // 最大重试次数
  static const int _maxImages = 8; // 最大图片数量
  static const int _deleteRetries = 2; // 删除文件最大重试次数
  static const Duration _retryDelay = Duration(milliseconds: 300); // 重试延迟时间
  static const int _maxConcurrentDeletes = 3; // 最大并发删除任务数

  static String? _cachedLocalStoragePath; // 缓存本地存储路径
  static List<String>? _cachedTodayImages; // 缓存当天的图片列表
  static List<String>? _cachedAllImages; // 缓存所有图片列表

  // 获取本地存储路径，若不存在则创建
  static Future<String> _getLocalStoragePath() async {
    if (_cachedLocalStoragePath != null) {
      return _cachedLocalStoragePath!;
    }
    final directory = await getApplicationDocumentsDirectory();
    final bingDir = Directory('${directory.path}/bing_images');
    if (!await bingDir.exists()) {
      await bingDir.create(recursive: true);
    }
    _cachedLocalStoragePath = bingDir.path;
    return _cachedLocalStoragePath!;
  }

  // 根据日期和序号生成文件名
  static String _generateFileName(int index) {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seqStr = (index + 1).toString().padLeft(2, '0');
    return '$dateStr$seqStr';
  }

  // 获取当天本地图片列表，支持缓存
  static Future<List<String>> _getLocalImagesForToday() async {
    if (_cachedTodayImages != null) {
      LogUtil.i('使用缓存的当天图片列表');
      return _cachedTodayImages!;
    }
    final dirPath = await _getLocalStoragePath();
    final todayPrefix = _generateFileName(0).substring(0, 8);
    final files = await _listDirectoryFiles(dirPath);
    
    _cachedTodayImages = files
        .where((file) => file.path.contains(todayPrefix) && file.path.endsWith('.jpg'))
        .map((file) => file.path)
        .toList()
      ..sort();
    return _cachedTodayImages!;
  }

  // 获取所有本地图片列表，支持缓存
  static Future<List<String>> _getAllLocalImages() async {
    if (_cachedAllImages != null) {
      LogUtil.i('使用缓存的所有图片列表');
      return _cachedAllImages!;
    }
    final dirPath = await _getLocalStoragePath();
    final files = await _listDirectoryFiles(dirPath);
    
    _cachedAllImages = files
        .where((file) => file.path.endsWith('.jpg'))
        .map((file) => file.path)
        .toList()
      ..sort();
    return _cachedAllImages!;
  }

  // 列出指定目录下的所有文件
  static Future<List<FileSystemEntity>> _listDirectoryFiles(String dirPath) async {
    final dir = Directory(dirPath);
    return await dir.list().toList();
  }

  // 删除非当天的旧图片，限制并发删除数量
  static Future<void> _deleteOldImages() async {
    final dirPath = await _getLocalStoragePath();
    final todayPrefix = _generateFileName(0).substring(0, 8);
    final files = await _listDirectoryFiles(dirPath);

    final deleteTasks = <Future<void>>[];
    for (final file in files) {
      if (file is File && !file.path.contains(todayPrefix)) {
        deleteTasks.add((() async {
          for (int retry = 0; retry < _deleteRetries; retry++) {
            try {
              await file.delete();
              LogUtil.i('删除旧图片: ${file.path}');
              break;
            } catch (e) {
              if (retry == _deleteRetries - 1) {
                LogUtil.logError('删除旧图片失败: ${file.path}，已达最大重试次数', e);
              } else {
                await Future.delayed(_retryDelay);
              }
            }
          }
        })());
      }
    }

    for (int i = 0; i < deleteTasks.length; i += _maxConcurrentDeletes) {
      final batch = deleteTasks.sublist(i, (i + _maxConcurrentDeletes).clamp(0, deleteTasks.length));
      await Future.wait(batch);
    }
    _cachedTodayImages = null; // 清理当天图片缓存
    _cachedAllImages = null; // 清理所有图片缓存
  }

  // 下载并保存图片到本地，返回文件路径
  static Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final dirPath = await _getLocalStoragePath();
      final filePath = '$dirPath/$fileName.jpg';
      LogUtil.i('开始下载图片: $url 到 $filePath');

      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response?.statusCode == 200 && response?.data is List<int>) {
        final file = File(filePath);
        await file.writeAsBytes(response!.data as List<int>);
        LogUtil.i('图片下载并保存成功: $filePath');
        _cachedTodayImages = null; // 清理缓存
        _cachedAllImages = null; // 清理缓存
        return filePath;
      }
      return null;
    } catch (e) {
      LogUtil.logError('下载图片失败: $url', e);
      return null;
    }
  }

  // 当下载失败时回退到本地已有图片
  static Future<List<String>> _fallbackToLocalImages() async {
    final allLocalImages = await _getAllLocalImages();
    if (allLocalImages.isNotEmpty) {
      bingImgUrls = allLocalImages;
      LogUtil.i('回退使用本地已有图片');
      return bingImgUrls;
    }
    LogUtil.e('无本地图片可用');
    return [];
  }

  // 获取多张 Bing 图片 URL 并下载
  static Future<List<String>> getBingImgUrls({String? channelId}) async {
    try {
      List<String> localImages = await _getLocalImagesForToday();
      if (localImages.length == _maxImages) {
        LogUtil.i('使用本地缓存的当天图片');
        bingImgUrls = localImages;
        return bingImgUrls;
      }

      const int maxConcurrentDownloads = 4; // 最大并发下载数
      List<Future<List<String?>>> batches = [];
      for (int i = 0; i < _maxImages; i += maxConcurrentDownloads) {
        final batchEnd = (i + maxConcurrentDownloads).clamp(0, _maxImages);
        final batchRequests = <Future<String?>>[];
        for (int j = i; j < batchEnd; j++) {
          batchRequests.add(_fetchBingImageUrlWithRetry(j, 0, channelId).then((url) async {
            if (url != null) {
              final fileName = _generateFileName(j);
              return await _downloadAndSaveImage(url, fileName);
            }
            return null;
          }));
        }
        batches.add(Future.wait(batchRequests));
      }

      final results = await Future.wait(batches);
      final paths = results
          .expand((batch) => batch)
          .where((path) => path != null)
          .cast<String>()
          .toList();

      if (paths.isNotEmpty) {
        await _deleteOldImages();
        bingImgUrls = paths;
        LogUtil.i('新图片下载成功，已更新 bingImgUrls');
      } else {
        return await _fallbackToLocalImages();
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片时发生错误', e, stackTrace);
      return await _fallbackToLocalImages();
    }
  }

  // 获取单张 Bing 图片 URL，支持重试机制
  static Future<String?> _fetchBingImageUrlWithRetry(int idx, [int retryCount = 0, String? channelId]) async {
    try {
      final baseUrl = 'https://bing.biturl.top/?resolution=1366&format=json&index=$idx';
      final url = channelId != null ? '$baseUrl&channelId=$channelId' : baseUrl;
      
      final res = await HttpUtil().getRequest(url);
      final imageUrl = res?['url']?.isNotEmpty ?? false ? res['url'] : null;

      if (imageUrl != null && Uri.tryParse(imageUrl)?.hasAbsolutePath == true) {
        return imageUrl;
      }
      throw Exception('无效的图片 URL: $imageUrl');
    } catch (e) {
      if (retryCount < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 200 * (retryCount + 1)));
        return _fetchBingImageUrlWithRetry(idx, retryCount + 1, channelId);
      }
      LogUtil.logError('获取第 $idx 张 Bing 图片 URL 时发生错误', e);
      return null;
    }
  }

  // 获取单张 Bing 图片并下载，优先使用本地缓存
  static Future<String?> getBingImgUrl({String? channelId}) async {
    try {
      final localImages = await _getLocalImagesForToday();
      if (localImages.isNotEmpty) {
        bingImgUrl = localImages.first;
        return bingImgUrl;
      }

      final url = await _fetchBingImageUrlWithRetry(0, 0, channelId);
      if (url != null) {
        final fileName = _generateFileName(0);
        bingImgUrl = await _downloadAndSaveImage(url, fileName);
        if (bingImgUrl != null) {
          await _deleteOldImages();
        }
        return bingImgUrl;
      }

      final allLocalImages = await _getAllLocalImages();
      if (allLocalImages.isNotEmpty) {
        bingImgUrl = allLocalImages.first;
        LogUtil.i('新图片下载失败，回退使用本地已有图片');
        return bingImgUrl;
      }

      LogUtil.e('未能获取 Bing 图片，且无本地图片可用');
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片时发生错误', e, stackTrace);
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
      _cachedTodayImages = null; // 清理当天图片缓存
      _cachedAllImages = null; // 清理所有图片缓存
      final dirPath = await _getLocalStoragePath();
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        LogUtil.i('已清除所有本地 Bing 图片缓存');
      }
    } catch (e) {
      LogUtil.logError('清除 Bing 图片缓存时发生错误', e);
    }
  }
}
