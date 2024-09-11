import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';  // 用于缓存数据
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 存储 Bing 背景图片 URL
  static const cacheDuration = Duration(hours: 3); // 缓存有效期 3 小时

  // 获取最多 15 张 Bing 图片的 URL
  static Future<List<String>> getBingImgUrls() async {
    try {
      if (bingImgUrls.isNotEmpty) {
        LogUtil.i('从缓存中获取 Bing 图片 URLs');
        return bingImgUrls;
      }

      List<String> urls = [];
      for (int i = 0; i < 15; i++) {
        final res = await HttpUtil().getRequest('https://bing.biturl.top/?idx=$i');
        if (res != null && res['url'] != null && res['url'] != '') {
          urls.add(res['url']);
        }
      }

      if (urls.isNotEmpty) {
        LogUtil.i('成功获取到 ${urls.length} 张 Bing 图片 URLs');
      } else {
        LogUtil.w('未能获取到 Bing 图片 URLs');
      }

      bingImgUrls = urls;
      return bingImgUrls;
    } catch (e, stackTrace) {
      logError('获取 Bing 图片 URLs 时发生错误', e, stackTrace);
      return [];
    }
  }

  // 只获取一张 Bing 背景图片的 URL
  static Future<String?> getBingImgUrl() async {
    try {
      if (bingImgUrl != null && bingImgUrl != '') {
        LogUtil.i('从缓存中获取 Bing 图片 URL');
        return bingImgUrl;
      }

      final res = await HttpUtil().getRequest('https://bing.biturl.top/');
      if (res != null && res['url'] != null && res['url'] != '') {
        bingImgUrl = res['url'];
        LogUtil.i('成功获取 Bing 图片 URL: $bingImgUrl');
        return bingImgUrl;
      } else {
        LogUtil.w('未能获取 Bing 图片 URL');
      }
      return null;
    } catch (e, stackTrace) {
      logError('获取 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }

  // 从缓存中获取 Bing 背景图片的 URL，带缓存时间检查
  static Future<String?> getCachedBingImgUrl() async {
    try {
      // 获取缓存的 URL 和时间戳
      String? cachedUrl = SpUtil.getString('bingImgUrl', defValue: null);
      int? cacheTime = SpUtil.getInt('bingImgUrlCacheTime', defValue: 0);

      // 检查缓存是否过期
      if (cachedUrl != null && cachedUrl != '') {
        DateTime cachedDate = DateTime.fromMillisecondsSinceEpoch(cacheTime ?? 0);
        if (DateTime.now().difference(cachedDate) < cacheDuration) {
          LogUtil.i('缓存未过期，使用缓存的 Bing 图片 URL');
          return cachedUrl; // 缓存未过期，返回缓存的 URL
        } else {
          LogUtil.i('缓存已过期，准备获取新的 Bing 图片 URL');
        }
      }

      // 如果缓存过期或没有缓存，获取新的 URL
      String? newBingImgUrl = await getBingImgUrl();
      if (newBingImgUrl != null) {
        // 将新的 URL 和当前时间戳缓存起来
        await SpUtil.putString('bingImgUrl', newBingImgUrl);
        await SpUtil.putInt('bingImgUrlCacheTime', DateTime.now().millisecondsSinceEpoch);
        LogUtil.i('成功缓存新的 Bing 图片 URL');
      }

      return newBingImgUrl;
    } catch (e, stackTrace) {
      logError('获取缓存的 Bing 图片 URL 时发生错误', e, stackTrace);
      return null;
    }
  }
}