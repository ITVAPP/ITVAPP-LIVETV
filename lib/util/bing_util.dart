import 'dart:async';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 存储 Bing 背景图片 URL
  static const cacheDuration = Duration(hours: 12); // 缓存有效期 12 小时
  static const _maxRetries = 3; // 新增：最大重试次数
  static const _cacheKeyUrls = 'bingImgUrls'; // 新增：缓存键常量
  static const _cacheKeyUrlsTime = 'bingImgUrlsCacheTime'; // 新增：缓存时间键常量
  static const _cacheKeySingleUrl = 'bingImgUrl'; // 新增：单张图片缓存键
  static const _cacheKeySingleUrlTime = 'bingImgUrlCacheTime'; // 新增：单张图片缓存时间键

  // 新增：检查缓存是否有效的方法
  static bool _isCacheValid(int? cacheTime) {
    if (cacheTime == null || cacheTime == 0) return false;
    final cachedDate = DateTime.fromMillisecondsSinceEpoch(cacheTime);
    return DateTime.now().difference(cachedDate) < cacheDuration;
  }

  // 获取最多 8 张 Bing 图片的 URL
  static Future<List<String>> getBingImgUrls() async {
    try {
      // 检查是否有缓存的图片 URL 列表
      if (bingImgUrls.isNotEmpty) {
        return bingImgUrls;
      }

      // 尝试从本地缓存中读取
      String? cachedUrlList = SpUtil.getString(_cacheKeyUrls, defValue: null);
      int? cacheTime = SpUtil.getInt(_cacheKeyUrlsTime, defValue: 0);

      // 使用统一的缓存验证
      if (cachedUrlList?.isNotEmpty ?? false && _isCacheValid(cacheTime)) {
        LogUtil.i('缓存未过期，使用缓存的 Bing 图片 URL 列表');
        bingImgUrls = cachedUrlList!.split(',');
        return bingImgUrls;
      }

      // 发起新的网络请求，最多获取 8 张图片
      List<Future<String?>> requests = [];
      for (int i = 0; i <= 7; i++) {
        requests.add(_fetchBingImageUrlWithRetry(i));  // 使用带重试的请求方法
      }

      // 等待所有请求完成并收集有效的 URL
      List<String> urls = (await Future.wait(requests)).where((url) => url != null).cast<String>().toList();

      if (urls.isNotEmpty) {
        bingImgUrls = urls;
        // 异步缓存，不阻塞主流程
        _cacheUrls(urls);
      } else {
        LogUtil.e('未能获取到 Bing 图片 URLs');
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片 URLs 时发生错误', e, stackTrace);
      // 发生错误时尝试返回缓存
      String? cachedUrlList = SpUtil.getString(_cacheKeyUrls);
      return cachedUrlList?.split(',') ?? [];
    }
  }

  // 新增：异步缓存 URL 列表
  static Future<void> _cacheUrls(List<String> urls) async {
    try {
      await Future.wait([
        SpUtil.putString(_cacheKeyUrls, urls.join(',')),
        SpUtil.putInt(_cacheKeyUrlsTime, DateTime.now().millisecondsSinceEpoch),
      ]);
    } catch (e) {
      LogUtil.logError('缓存 Bing 图片 URLs 时发生错误', e);
    }
  }

  // 优化：带重试机制的图片 URL 获取
  static Future<String?> _fetchBingImageUrlWithRetry(int idx, [int retryCount = 0]) async {
    try {
      final res = await HttpUtil().getRequest('https://bing.biturl.top/?resolution=1366&format=json&index=$idx');
      return res?['url']?.isNotEmpty ?? false ? res['url'] : null;
    } catch (e) {
      if (retryCount < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 200 * (retryCount + 1)));
        return _fetchBingImageUrlWithRetry(idx, retryCount + 1);
      }
      LogUtil.logError('获取第 $idx 张 Bing 图片 URL 时发生错误', e);
      return null;
    }
  }

  // 只获取一张 Bing 背景图片的 URL
  static Future<String?> getBingImgUrl() async {
    try {
      if (bingImgUrl?.isNotEmpty ?? false) {
        return bingImgUrl;
      }

      final res = await _fetchBingImageUrlWithRetry(0);  // 使用带重试的请求方法
      if (res != null) {
        bingImgUrl = res;
        await _cacheSingleUrl(res);  // 使用异步缓存
        LogUtil.i('成功获取 Bing 图片 URL: $bingImgUrl');
        return bingImgUrl;
      } else {
        LogUtil.e('未能获取 Bing 图片 URL');
        return null;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }

  // 新增：异步缓存单个 URL
  static Future<void> _cacheSingleUrl(String url) async {
    try {
      await Future.wait([
        SpUtil.putString(_cacheKeySingleUrl, url),
        SpUtil.putInt(_cacheKeySingleUrlTime, DateTime.now().millisecondsSinceEpoch),
      ]);
    } catch (e) {
      LogUtil.logError('缓存单个 Bing 图片 URL 时发生错误', e);
    }
  }

  // 从缓存中获取 Bing 背景图片的 URL，带缓存时间检查
  static Future<String?> getCachedBingImgUrl() async {
    try {
      String? cachedUrl = SpUtil.getString(_cacheKeySingleUrl, defValue: null);
      int? cacheTime = SpUtil.getInt(_cacheKeySingleUrlTime, defValue: 0);

      if (cachedUrl?.isNotEmpty ?? false && _isCacheValid(cacheTime)) {
        return cachedUrl;
      }

      String? newBingImgUrl = await getBingImgUrl();
      if (newBingImgUrl != null) {
        await _cacheSingleUrl(newBingImgUrl);
      }

      return newBingImgUrl;
    } catch (e, stackTrace) {
      LogUtil.logError('获取缓存的 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }

  // 新增：清除缓存方法
  static Future<void> clearCache() async {
    try {
      bingImgUrls = [];
      bingImgUrl = null;
      await Future.wait([
        SpUtil.remove(_cacheKeyUrls),
        SpUtil.remove(_cacheKeyUrlsTime),
        SpUtil.remove(_cacheKeySingleUrl),
        SpUtil.remove(_cacheKeySingleUrlTime),
      ]);
    } catch (e) {
      LogUtil.logError('清除 Bing 图片缓存时发生错误', e);
    }
  }
}
