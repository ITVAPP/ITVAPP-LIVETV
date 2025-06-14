/// 规则配置类，包含过滤规则、特殊规则、动态关键字等配置
class M3U8Rules {
  const M3U8Rules._();

  /// 检测地址优先规则 - 关键字|必需关键字
  /// 格式：输入URL或检测URL任一包含的关键字|检测URL包含的关键字
  static const List<String> rulePatterns = [
    '@@BRTV新闻|btv_sn_20170706_s9',
    '@@BRTV文艺|btv_sn_20170706_s2',
    '@@BRTV i生活|btv_sn_20170706_s7',
    '@@BRTV纪实科教|btv_sn_20170706_s3',
    '@@BRTV财经|btv_sn_20170706_s5',
    '@@BRTV体育休闲|btv_sn_20170706_s6',
    '@@卡酷少儿|btv_sn_20170706_s10',
    'zjwtv.com|m3u8?domain=',
    'sztv.com.cn|m3u8?sign=',
    '4gtv.tv|master.m3u8',
    'tcrbs.com|auth_key',
    'xybtv.com|auth_key',
    'aodianyun.com|auth_key',
    'ptbtv.com|hd/live',
    'setv.sh.cn|programme10_ud',
    'kanwz.net|playlist.m3u8',
    'sxtygdy.com|tytv-hls.sxtygdy.com',
    'tvlive.yntv.cn|chunks_dvr_range',
    'appwuhan.com|playlist.m3u8',
    'hbtv.com.cn/new-|aalook=',
  ];

  /// 特殊规则模式 - 域名|文件类型
  /// 格式：关键字|文件扩展名
  static const List<String> specialRulePatterns = [
    'nctvcloud.com|flv',
    'iptv345.com|flv',
  ];

  /// 动态关键字 - 触发自定义M3U8获取的关键字
  static const List<String> dynamicKeywords = [
    'sousuo',
    'jinan',
    'gansu',
    'xizang',
    'sichuan',
    'xishui',
    'yanan',
    'foshan',
    'shantou',
  ];

  /// 白名单扩展名 - 允许加载的特殊扩展名
  static const List<String> whiteExtensions = [
    'r.png?t=',
    'www.hljtv.com',
    'guangdianyun.tv',
  ];

  /// 屏蔽扩展名 - 禁止加载的文件扩展名
  static const List<String> blockedExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.css',
    '.woff',
    '.woff2',
    '.ttf',
    '.eot',
    '.ico',
    '.svg',
    '.mp3',
    '.wav',
    '.pdf',
    '.doc',
    '.docx',
    '.swf',
  ];

  /// 无效模式 - 广告、跟踪等无效URL模式
  static const List<String> invalidPatterns = [
    'advertisement',
    'analytics',
    'tracker',
    'pixel',
    'beacon',
    'stats',
    'google',
  ];
}
