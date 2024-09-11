import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:sp_util/sp_util.dart';  // 用于缓存数据

class BingUtil {
  static String? bingImgUrl;

  static Future<String?> getBingImgUrl() async {
    if (bingImgUrl != null && bingImgUrl != '') return bingImgUrl;
    final res = await HttpUtil().getRequest('https://bing.biturl.top/', isShowLoading: false);
    if (res != null && res['url'] != null && res['url'] != '') {
      bingImgUrl = res['url'];
      return bingImgUrl;
    }
    return null;
  }
}
