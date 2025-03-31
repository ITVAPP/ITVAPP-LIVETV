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
  static const _maxRetries = 2;
  static const _maxImages = 8;

  static Future<String> _getLocalStoragePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final bingDir = Directory('${directory.path}/bing_images');
    if (!await bingDir.exists()) {
      await bingDir.create(recursive: true);
    }
    return bingDir.path;
  }

  static String _generateFileName(int index) {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seqStr = (index + 1).toString().padLeft(2, '0');
    return '$dateStr$seqStr';
  }

  static Future<List<String>> _getLocalImagesForToday() async {
    final dirPath = await _getLocalStoragePath();
    final dir = Directory(dirPath);
    final todayPrefix = _generateFileName(0).substring(0, 8);
    final files = await dir.list().toList();
    
    return files
        .where((file) => file.path.contains(todayPrefix) && file.path.endsWith('.jpg'))
        .map((file) => file.path)
        .toList()
      ..sort();
  }

  static Future<void> _deleteOldImages() async {
    final dirPath = await _getLocalStoragePath();
    final dir = Directory(dirPath);
    final todayPrefix = _generateFileName(0).substring(0, 8);
    final files = await dir.list().toList();

    for (final file in files) {
      if (file is File && !file.path.contains(todayPrefix)) {
        for (int retry = 0; retry < 3; retry++) {
          try {
            await file.delete();
            LogUtil.i('删除旧图片: ${file.path}');
            break;
          } catch (e) {
            if (retry == 2) {
              LogUtil.logError('删除旧图片失败: ${file.path}，已达最大重试次数', e);
            } else {
              await Future.delayed(Duration(milliseconds: 100));
            }
          }
        }
      }
    }
  }

  static Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(responseType: ResponseType.bytes), // 使用 dio 的 Options
      );
      if (response?.statusCode == 200 && response?.data is List<int>) {
        final dirPath = await _getLocalStoragePath();
        final filePath = '$dirPath/$fileName.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response!.data as List<int>);
        return filePath;
      }
      return null;
    } catch (e) {
      LogUtil.logError('下载图片失败: $url', e);
      return null;
    }
  }

  static Future<List<String>> getBingImgUrls({String? channelId}) async {
    try {
      List<String> localImages = await _getLocalImagesForToday();
      if (localImages.length == _maxImages) {
        LogUtil.i('使用本地缓存的当天图片');
        bingImgUrls = localImages;
        return bingImgUrls;
      }

      await _deleteOldImages();

      List<Future<String?>> requests = [];
      for (int i = 0; i < _maxImages; i++) {
        requests.add(_fetchBingImageUrlWithRetry(i, 0, channelId).then((url) async {
          if (url != null) {
            final fileName = _generateFileName(i);
            return await _downloadAndSaveImage(url, fileName);
          }
          return null;
        }));
      }

      final paths = (await Future.wait(requests))
          .where((path) => path != null)
          .cast<String>()
          .toList();

      if (paths.isNotEmpty) {
        bingImgUrls = paths;
      } else {
        LogUtil.e('未能获取到 Bing 图片');
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片时发生错误', e, stackTrace);
      return await _getLocalImagesForToday();
    }
  }

  static Future<String?> _fetchBingImageUrlWithRetry(int idx, [int retryCount = 0, String? channelId]) async {
    try {
      final baseUrl = 'https://bing.biturl.top/?resolution=1366&format=json&index=$idx';
      final url = channelId != null ? '$baseUrl&channelId=$channelId' : baseUrl;
      
      final res = await HttpUtil().getRequest(url);
      return res?['url']?.isNotEmpty ?? false ? res['url'] : null;
    } catch (e) {
      if (retryCount < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 200 * (retryCount + 1)));
        return _fetchBingImageUrlWithRetry(idx, retryCount + 1, channelId);
      }
      LogUtil.logError('获取第 $idx 张 Bing 图片 URL 时发生错误', e);
      return null;
    }
  }

  static Future<String?> getBingImgUrl({String? channelId}) async {
    try {
      final localImages = await _getLocalImagesForToday();
      if (localImages.isNotEmpty) {
        bingImgUrl = localImages.first;
        return bingImgUrl;
      }

      await _deleteOldImages();
      final url = await _fetchBingImageUrlWithRetry(0, 0, channelId);
      if (url != null) {
        final fileName = _generateFileName(0);
        bingImgUrl = await _downloadAndSaveImage(url, fileName);
        return bingImgUrl;
      }
      LogUtil.e('未能获取 Bing 图片');
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片时发生错误', e, stackTrace);
      return null;
    }
  }

  static Future<void> clearCache() async {
    try {
      bingImgUrls = [];
      bingImgUrl = null;
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
