import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';  // 用于缓存数据

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 存储 Bing 背景图片 URL

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

  // 新增：从缓存中获取 Bing 背景图片的 URL
  static Future<String?> getCachedBingImgUrl() async {
    // 优先从缓存中获取 URL
    String? cachedUrl = SpUtil.getString('bingImgUrl', defValue: null);
    if (cachedUrl != null && cachedUrl != '') {
      return cachedUrl;
    }

    // 如果缓存中没有，则调用 getBingImgUrl 获取新的 URL
    String? newBingImgUrl = await getBingImgUrl();
    if (newBingImgUrl != null) {
      // 将新的 URL 缓存起来
      await SpUtil.putString('bingImgUrl', newBingImgUrl);
    }

    return newBingImgUrl;
  }
}
