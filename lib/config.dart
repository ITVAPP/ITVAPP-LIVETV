class Config {
  /// 当前应用版本
  static const String version = '1.5.8';

  /// 当前应用域名（使用某些流量统计API时可以使用）
  static const String hostname = 'livetv.itvapp.net';
  
  /// 定义收藏列表的本地缓存键
  static const String favoriteCacheKey = 'favorite_m3u_cache';

  /// 定义播放列表的本地缓存键
  static const String m3uCacheKey = 'm3u_cache';

  /// 定义收藏列表的分类名称
  static const String myFavoriteKey = 'myFavorite';

  /// 定义播放列表无分类时的分类名称
  static const String allChannelsKey = 'allChannels';

  /// 默认的日志功能开关
  static const bool defaultLogOn = true;

  /// 默认是否启用 Bing 背景
  static const bool defaultBingBg = false;

  /// 默认文本缩放比例
  static const double defaultTextScaleFactor = 1.0;

  /// 默认字体
  static const String defaultFontFamily = 'system';
}
