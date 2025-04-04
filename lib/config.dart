class Config {
  /// 当前应用版本
  static const String version = '1.5.8';

  /// 当前应用域名（使用某些流量统计API时可以使用）
  static const String hostname = 'livetv.itvapp.net';

  /// 当前应用包名（和 MainActivity.kt 设置的要一致）
  static const String packagename = "net.itvapp.livetv";
  
  /// 升级检查地址
  static const String upgradeUrl = 'https://cdn.itvapp.net/itvapp_live_tv/upgrade.json';
  
  /// 定义收藏列表的本地缓存键
  static const String favoriteCacheKey = 'favorite_m3u_cache';

  /// 定义播放列表的本地缓存键
  static const String m3uCacheKey = 'm3u_cache';

  /// 定义收藏列表的分类名称
  static const String myFavoriteKey = 'myFavorite';

  /// 定义播放列表无分类时的分类名称
  static const String allChannelsKey = 'allChannels';

  /// 流量统计开关（需正确设置流量统计API才可以使用）
  static const bool Analytics = true;

  /// 默认的日志功能开关
  static const bool defaultLogOn = true;

  /// 默认是否启用 Bing 背景
  static const bool defaultBingBg = false;

  /// 默认文本缩放比例
  static const double defaultTextScaleFactor = 1.0;

  /// 默认字体
  static const String defaultFontFamily = 'system';

  /// M3U 文件 URL 的 XOR 加密密钥
  static const String m3uXorKey = 'itvapp-livetv-secret-2025'; // 自定义密钥

  /// 广告 API 地址
  static const String adApiUrl = 'https://your-api.com/ads';

  /// 文字广告显示次数的本地缓存键
  static const String textAdCountKey = 'text_ad_shown_count';

  /// 视频广告显示次数的本地缓存键
  static const String videoAdCountKey = 'video_ad_shown_count';
}
