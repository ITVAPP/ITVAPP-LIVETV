import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'dart:async';

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 存储 Bing 背景图片 URL
  static const cacheDuration = Duration(hours: 12); // 缓存有效期 12 小时

  // 获取最多 8 张 Bing 图片的 URL
  static Future<List<String>> getBingImgUrls() async {
    try {
      // 检查是否有缓存的图片 URL 列表
      if (bingImgUrls.isNotEmpty) {
        return bingImgUrls;
      }

      // 尝试从本地缓存中读取
      String? cachedUrlList = SpUtil.getString('bingImgUrls', defValue: null);
      int? cacheTime = SpUtil.getInt('bingImgUrlsCacheTime', defValue: 0);

      // 优化缓存过期检查
      if (cachedUrlList != null && cachedUrlList.isNotEmpty && cacheTime != null && cacheTime > 0) {
        DateTime cachedDate = DateTime.fromMillisecondsSinceEpoch(cacheTime);
        if (DateTime.now().difference(cachedDate) < cacheDuration) {
          LogUtil.i('缓存未过期，使用缓存的 Bing 图片 URL 列表');
          bingImgUrls = cachedUrlList.split(','); // 从缓存中读取列表
          return bingImgUrls;
        }
      }

      // 发起新的网络请求，最多获取 8 张图片
      List<Future<String?>> requests = [];
      for (int i = 0; i <= 7; i++) {  // 修改为获取 0 - 7 索引的图片
        requests.add(_fetchBingImageUrl(i));
      }

      // 等待所有请求完成并收集有效的 URL
      List<String> urls = (await Future.wait(requests)).where((url) => url != null).cast<String>().toList();

      if (urls.isNotEmpty) {
        bingImgUrls = urls;

        // 缓存新的图片列表
        await SpUtil.putString('bingImgUrls', bingImgUrls.join(','));
        await SpUtil.putInt('bingImgUrlsCacheTime', DateTime.now().millisecondsSinceEpoch);
      } else {
        LogUtil.e('未能获取到 Bing 图片 URLs');
      }

      return bingImgUrls;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片 URLs 时发生错误', e, stackTrace);
      return [];
    }
  }

  // 发送单个请求获取 Bing 图片 URL
  static Future<String?> _fetchBingImageUrl(int idx) async {
    try {
      final res = await HttpUtil().getRequest('https://bing.biturl.top/?resolution=1366&format=json&index=$idx');
      return res?.['url']?.isNotEmpty ?? false ? res['url'] : null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取第 $idx 张 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }

  // 只获取一张 Bing 背景图片的 URL
  static Future<String?> getBingImgUrl() async {
    try {
      if (bingImgUrl?.isNotEmpty ?? false) {
        return bingImgUrl;
      }

      final res = await HttpUtil().getRequest('https://bing.biturl.top/?resolution=1366&format=json&index=0');
      if (res?.['url']?.isNotEmpty ?? false) {
        bingImgUrl = res['url'];
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

  // 从缓存中获取 Bing 背景图片的 URL，带缓存时间检查
  static Future<String?> getCachedBingImgUrl() async {
    try {
      // 获取缓存的 URL 和时间戳
      String? cachedUrl = SpUtil.getString('bingImgUrl', defValue: null);
      int? cacheTime = SpUtil.getInt('bingImgUrlCacheTime', defValue: 0);

      // 优化缓存判断条件
      if (cachedUrl?.isNotEmpty ?? false && cacheTime != null && cacheTime > 0) {
        DateTime cachedDate = DateTime.fromMillisecondsSinceEpoch(cacheTime);
        if (DateTime.now().difference(cachedDate) < cacheDuration) {
          return cachedUrl; // 缓存未过期，返回缓存的 URL
        } else {
          LogUtil.i('缓存已过期，准备获取新的 Bing 图片 URL');
        }
      }

      // 如果缓存过期或没有缓存，获取新的 URL
      String? newBingImgUrl = await getBingImgUrl();
      if (newBingImgUrl != null) {
        await SpUtil.putString('bingImgUrl', newBingImgUrl);
        await SpUtil.putInt('bingImgUrlCacheTime', DateTime.now().millisecondsSinceEpoch);
      }

      return newBingImgUrl;
    } catch (e, stackTrace) {
      LogUtil.logError('获取缓存的 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }
}
