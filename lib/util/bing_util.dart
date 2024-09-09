import 'package:itvapp_live_tv/util/http_util.dart';

class BingUtil {
  static List<String> bingImgUrls = [];
  static String? bingImgUrl; // 修复：定义 bingImgUrl

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

  // 只获取一张 Bing 背景图片的 URL（旧方法保留）
  static Future<String?> getBingImgUrl() async {
    // 修复：检查 bingImgUrl 是否为 null，如果不是，则直接返回
    if (bingImgUrl != null && bingImgUrl != '') return bingImgUrl;

    // 获取新的 Bing 图片 URL
    final res = await HttpUtil().getRequest('https://bing.biturl.top/');
    if (res != null && res['url'] != null && res['url'] != '') {
      bingImgUrl = res['url']; // 修复：存储新获取的 URL
      return bingImgUrl;
    }
    return null;
  }
}
