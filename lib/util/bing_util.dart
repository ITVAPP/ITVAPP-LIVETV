import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl;
  static const int _maxRetries = 2; // 将魔法数字抽取为常量
  static const int _maxImages = 8;
  static const int _deleteRetries = 3; // 删除文件重试次数常量
  static const Duration _retryDelay = Duration(milliseconds: 100); // 重试延迟常量

  static String? _cachedLocalStoragePath;
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

  static String _generateFileName(int index) {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seqStr = (index + 1).toString().padLeft(2, '0');
    return '$dateStr$seqStr';
  }

  static Future<List<String>> _getLocalImagesForToday() async {
    final dirPath = await _getLocalStoragePath();
    final todayPrefix = _generateFileName(0).substring(0, 8);
    final files = await _listDirectoryFiles(dirPath);
    
    final localImages = files
        .where((file) => file.path.contains(todayPrefix) && file.path.endsWith('.jpg'))
        .map((file) => file.path)
        .toList()
      ..sort();
    return localImages;
  }

  // 修改代码开始
  // 新增方法：获取所有本地图片（包括旧日期）
  static Future<List<String>> _getAllLocalImages() async {
    final dirPath = await _getLocalStoragePath();
    final files = await _listDirectoryFiles(dirPath);
    
    final allImages = files
        .where((file) => file.path.endsWith('.jpg'))
        .map((file) => file.path)
        .toList()
      ..sort(); // 按文件名排序，旧日期在前，新日期在后
    return allImages;
  }
  // 修改代码结束

  static Future<List<FileSystemEntity>> _listDirectoryFiles(String dirPath) async {
    final dir = Directory(dirPath);
    return await dir.list().toList();
  }

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
    await Future.wait(deleteTasks); // 异步批量删除
  }

  static Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final dirPath = await _getLocalStoragePath();
      final filePath = '$dirPath/$fileName.jpg';
      final file = File(filePath);

      // 检查文件是否已存在，避免重复下载
      if (await file.exists()) {
        LogUtil.i('图片已存在，无需重复下载: $filePath');
        return filePath;
      }

      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response?.statusCode == 200 && response?.data is List<int>) {
        await file.writeAsBytes(response!.data as List<int>);
        return filePath;
      }
      return null;
    } catch (e) {
      LogUtil.logError('下载图片失败: $url', e);
      return null;
    }
  }

  // 修改代码开始
  // 优化 getBingImgUrls，新图片下载成功后再删除旧图片，否则回退使用旧图片
  static Future<List<String>> getBingImgUrls({String? channelId}) async {
    try {
      List<String> localImages = await _getLocalImagesForToday();
      if (localImages.length == _maxImages) {
        LogUtil.i('使用本地缓存的当天图片');
        bingImgUrls = localImages;
        return bingImgUrls;
      }

      // 不提前删除旧图片，先尝试下载新图片
      const int batchSize = 4;
      List<Future<List<String?>>> batches = [];
      for (int i = 0; i < _maxImages; i += batchSize) {
        final batchEnd = (i + batchSize).clamp(0, _maxImages);
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
        // 新图片下载成功后删除旧图片
        await _deleteOldImages();
        bingImgUrls = paths;
        LogUtil.i('新图片下载成功，已更新 bingImgUrls');
      } else {
        // 下载失败，回退到所有本地图片
        final allLocalImages = await _getAllLocalImages();
        if (allLocalImages.isNotEmpty) {
          bingImgUrls = allLocalImages;
          LogUtil.i('新图片下载失败，回退使用本地已有图片');
        } else {
          LogUtil.e('未能获取到 Bing 图片，且无本地图片可用');
          bingImgUrls = [];
        }
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片时发生错误', e, stackTrace);
      final allLocalImages = await _getAllLocalImages();
      if (allLocalImages.isNotEmpty) {
        bingImgUrls = allLocalImages;
        return bingImgUrls;
      }
      return [];
    }
  }
  // 修改代码结束

  static Future<String?> _fetchBingImageUrlWithRetry(int idx, [int retryCount = 0, String? channelId]) async {
    try {
      final baseUrl = 'https://bing.biturl.top/?resolution=1366&format=json&index=$idx';
      final url = channelId != null ? '$baseUrl&channelId=$channelId' : baseUrl;
      
      final res = await HttpUtil().getRequest(url);
      final imageUrl = res?['url']?.isNotEmpty ?? false ? res['url'] : null;

      // 验证 URL 是否有效
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

  // 修改代码开始
  // 优化 getBingImgUrl，新图片下载成功后再删除旧图片，否则回退使用旧图片
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
          await _deleteOldImages(); // 单张下载成功后删除旧图片
        }
        return bingImgUrl;
      }

      // 下载失败，回退到所有本地图片
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
  // 修改代码结束

  static Future<void> clearCache() async {
    try {
      bingImgUrls = []; // 重置为新空列表
      bingImgUrl = null;
      _cachedLocalStoragePath = null; // 清理路径缓存
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


