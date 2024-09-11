import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';  // 用于缓存数据

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 存储 Bing 背景图片 URL
  static const cacheDuration = Duration(hours: 3); // 缓存有效期 3 小时

  // 获取最多 15 张 Bing 图片的 URL
  static Future<List<String>> getBingImgUrls() async {
    if (bingImgUrls.isNotEmpty) return bingImgUrls;

    List<String> urls = [];
    for (int i = 0; i < 15; i++) {
      final res = await HttpUtil().getRequest('https://bing.biturl.top/?idx=$i');
      if (res != null && res['url'] != null && res['url'] != '') {
        urls.add(res['url']);
      }
    }
    bingImgUrls = urls;
    return bingImgUrls;
  }

  // 只获取一张 Bing 背景图片的 URL
  static Future<String?> getBingImgUrl() async {
    if (bingImgUrl != null && bingImgUrl != '') return bingImgUrl;

    final res = await HttpUtil().getRequest('https://bing.biturl.top/');
    if (res != null && res['url'] != null && res['url'] != '') {
      bingImgUrl = res['url'];
      return bingImgUrl;
    }
    return null;
  }

  // 从缓存中获取 Bing 背景图片的 URL，带缓存时间检查
  static Future<String?> getCachedBingImgUrl() async {
    // 获取缓存的 URL 和时间戳
    String? cachedUrl = SpUtil.getString('bingImgUrl', defValue: null);
    int? cacheTime = SpUtil.getInt('bingImgUrlCacheTime', defValue: 0);

    // 检查缓存是否过期
    if (cachedUrl != null && cachedUrl != '') {
      DateTime cachedDate = DateTime.fromMillisecondsSinceEpoch(cacheTime ?? 0);
      if (DateTime.now().difference(cachedDate) < cacheDuration) {
        return cachedUrl; // 缓存未过期，返回缓存的 URL
      }
    }

    // 如果缓存过期或没有缓存，获取新的 URL
    String? newBingImgUrl = await getBingImgUrl();
    if (newBingImgUrl != null) {
      // 将新的 URL 和当前时间戳缓存起来
      await SpUtil.putString('bingImgUrl', newBingImgUrl);
      await SpUtil.putInt('bingImgUrlCacheTime', DateTime.now().millisecondsSinceEpoch);
    }

    return newBingImgUrl;
  }
}
