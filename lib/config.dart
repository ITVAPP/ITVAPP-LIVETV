class Config {
  /// 当前应用版本
  static const String version = '1.5.8';

  /// ICP备案号，如："京ICP备12345678号-1A"
  static const String icpRecord = null;

  /// 官网地址，如果为null则使用CheckVersionUtil.homeLink
  static const String homeUrl = null;

  /// 建议和反馈邮箱
  static const String officialEmail = 'support@yourapp.com';

  /// 合作联系邮箱（可选）
  static const String algorithmReportEmail = null;

  /// 当前应用域名（使用某些流量统计API时可以使用）
  static const String hostname = 'livetv.itvapp.net';

  /// 当前应用包名（和 MainActivity.kt 设置的要一致）
  static const String packagename = "net.itvapp.livetv";

  /// 是否需要生成国内版
  static const bool cnversion = true;

  /// 生成国内版时屏蔽播放列表的 分类和分组 关键字（多个用@分隔）
  static const String cnplayListrule = '香港@澳门@台湾@海外';
  
  /// 定义收藏列表的本地缓存键
  static const String favoriteCacheKey = 'favorite_m3u_cache';

  /// 定义播放列表的本地缓存键
  static const String m3uCacheKey = 'm3u_cache';

  /// 定义收藏列表的分类名称
  static const String myFavoriteKey = 'myFavorite';

  /// 定义播放列表无分类时的分类名称
  static const String allChannelsKey = 'allChannels';

  /// 设置播放列表默认语言（zh_CN/zh_TW/zh_HK/zh_MO，其他: 不转换）
  static const String playListlang = 'zh_CN';

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

  /// 默认的广告功能开关
  static const bool adOn = true;
  
  /// 存储广告计数的本地缓存键
  static const String adCountsKey = 'ad_counts_key';

  /// 广告 API 地址
  static const String adApiUrl = 'https://your-api.com/ads.json';

  /// 广告 API 备用地址
  static const String backupAdApiUrl = 'https://www.itvapp.net/itvapp_live_tv/ads.json';
  
  /// 升级检查地址
  static const String upgradeUrl = 'https://cdn.itvapp.net/itvapp_live_tv/upgrade.json';
  
  /// 升级检查备用地址
  static const String backupUpgradeUrl = 'https://www.itvapp.net/itvapp_live_tv/upgrade.json';
  
  /// EPG json数据获取地址
  static const String epgBaseUrl = 'https://iptv.crestekk.cn/epgphp/index.php/api/';

  /// EPG XML 地址，可以为null或空字符串
  static const String epgXmlUrl = '';
  
  /// 视频播放模式开关，true表示使用视频播放器，false表示使用音频播放器
  static const bool videoPlayMode = true;
}
