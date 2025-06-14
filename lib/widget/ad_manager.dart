import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

// 广告配置说明：定义通用参数和各类广告的行为
/* 广告配置说明
   - 通用参数：
     - id: 广告的唯一标识符，用于跟踪广告展示次数和区分不同广告
     - enabled: 布尔值，控制该广告是否启用
     - display_count: 整数，表示该广告最多可以展示的次数
     - link: 广告点击后跳转的URL链接
   - 文本广告：
     - 延迟 display_delay_seconds 秒后在应用顶部显示滚动文字
     - 最多显示 display_count 次
   - 视频广告：
     - 最多播放 display_count 次
   - 图片广告：
     - 延迟 display_delay_seconds 秒后在屏幕中央显示
     - 显示 duration_seconds 秒后自动关闭，期间显示倒计时
     - 最多显示 display_count 次
*/

// 定义广告类型：文字、图片、视频、无
enum AdType { text, image, video, none }

// 扩展广告类型，提供类型相关辅助方法
extension AdTypeExtension on AdType {
  // 获取类型字符串表示
  String get stringValue {
    switch (this) {
      case AdType.text: return 'text';
      case AdType.image: return 'image';
      case AdType.video: return 'video';
      case AdType.none: return 'none';
    }
  }
  
  // 获取类型中文显示名称
  String get displayName {
    switch (this) {
      case AdType.text: return '文字广告';
      case AdType.image: return '图片广告';
      case AdType.video: return '视频广告';
      case AdType.none: return '未知广告';
    }
  }
  
  // 获取类型默认延迟时间
  int get defaultDelay {
    switch (this) {
      case AdType.text: return AdManager.DEFAULT_TEXT_AD_DELAY;
      case AdType.image: return AdManager.DEFAULT_IMAGE_AD_DELAY;
      case AdType.video: return 0;
      case AdType.none: return 0;
    }
  }
  
  // 从字符串转换为广告类型
  static AdType fromString(String value) {
    switch (value) {
      case 'text': return AdType.text;
      case 'image': return AdType.image;
      case 'video': return AdType.video;
      default: return AdType.none;
    }
  }
}

// 广告类型参数辅助类
class _AdTypeParams {
  // 存储广告项列表
  final List<AdItem> adsList;
  // 日志信息前缀
  final String logPrefix;
  // 广告类型触发状态
  final bool hasTriggered;
  // 默认延迟时间（秒）
  final int defaultDelay;
  _AdTypeParams({required this.adsList, required this.logPrefix, required this.hasTriggered, required this.defaultDelay});
}

// 缓存图片尺寸的管理类
class _SizedImageCache {
  // 缓存最大容量
  final int maxSize;
  // 图片尺寸缓存映射
  final Map<String, Size> _cache = {};
  // 记录图片访问顺序
  final LinkedHashSet<String> _accessOrder = LinkedHashSet<String>();
  
  _SizedImageCache({this.maxSize = 30});
  
  // 获取指定图片的缓存尺寸
  Size? get(String key) {
    final size = _cache[key];
    if (size != null) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
    return size;
  }
  
  // 缓存图片尺寸，超出容量移除最旧项
  void set(String key, Size size) {
    if (_cache.length >= maxSize && !_cache.containsKey(key)) {
      _removeOldest();
    }
    
    _cache[key] = size;
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }
  
  // 移除最旧缓存项
  void _removeOldest() {
    if (_accessOrder.isNotEmpty) {
      final oldest = _accessOrder.first;
      _accessOrder.remove(oldest);
      _cache.remove(oldest);
    }
  }
  
  // 检查缓存是否包含指定键
  bool containsKey(String key) => _cache.containsKey(key);
  
  // 清空图片尺寸缓存
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }
}

// 单个广告项数据模型
class AdItem {
  // 广告唯一标识
  final String id;
  // 文字广告内容
  final String? content;
  // 视频或图片广告URL
  final String? url;
  // 广告启用状态
  final bool enabled;
  // 最大展示次数
  final int displayCount;
  // 展示延迟时间（秒）
  final int? displayDelaySeconds;
  // 图片广告显示时长（秒）
  final int? durationSeconds;
  // 点击跳转链接
  final String? link;
  // 广告类型：text、video、image
  final String type;

  const AdItem({
    required this.id,
    this.content,
    this.url,
    required this.enabled,
    required this.displayCount,
    this.displayDelaySeconds,
    this.durationSeconds,
    this.link,
    required this.type,
  });
}

// 广告数据模型
class AdData {
  // 文字广告列表
  final List<AdItem> textAds;
  // 视频广告列表
  final List<AdItem> videoAds;
  // 图片广告列表
  final List<AdItem> imageAds;

  const AdData({
    required this.textAds,
    required this.videoAds,
    required this.imageAds,
  });

  // 解析广告项列表
  static List<AdItem> _parseAdItems(List? adsList, String type, {
    String? idPrefix,
    bool needsContent = false,
    bool needsUrl = false,
  }) {
    if (adsList == null || adsList.isEmpty) return [];
    
    return adsList.map((item) {
      if (needsContent && (item['content'] == null || item['content'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少 content 字段，跳过');
        return null;
      }
      if (needsUrl && (item['url'] == null || item['url'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少 url 字段，跳过');
        return null;
      }
      final adId = item['id'] ?? '${idPrefix ?? type}_${DateTime.now().millisecondsSinceEpoch}';
      return AdItem(
        id: adId,
        content: item['content'],
        url: item['url'],
        enabled: item['enabled'] ?? false,
        displayCount: item['display_count'] ?? 0,
        displayDelaySeconds: item['display_delay_seconds'],
        durationSeconds: item['duration_seconds'] ?? 8,
        link: item['link'],
        type: type,
      );
    }).whereType<AdItem>().toList();
  }

  // 从 JSON 解析广告数据
  factory AdData.fromJson(Map<String, dynamic> json) {
    final data = json;
    return AdData(
      textAds: _parseAdItems(data['text_ads'] as List?, 'text', idPrefix: 'text', needsContent: true),
      videoAds: _parseAdItems(data['video_ads'] as List?, 'video', idPrefix: 'video', needsUrl: true),
      imageAds: _parseAdItems(data['image_ads'] as List?, 'image', idPrefix: 'image', needsUrl: true),
    );
  }
  
  // 判断广告数据是否为空
  bool get isEmpty => textAds.isEmpty && videoAds.isEmpty && imageAds.isEmpty;
}

// 管理广告展示次数
class AdCountManager {
  // 加载广告展示次数
  static Map<String, int> loadAdCounts() => {};

  // 保存广告展示次数
  static void saveAdCounts(Map<String, int> counts) {}

  // 增加广告展示计数
  static void incrementAdCount(String adId, Map<String, int> counts) {
    counts[adId] = (counts[adId] ?? 0) + 1;
  }
}

// 定时器管理类
class _TimerManager {
  // 存储定时器映射
  final Map<String, Timer> _timers = {};
  // 按类别存储定时器键
  final Map<String, Set<String>> _categories = {};
  
  // 添加定时器并归类
  void add(String key, Timer timer, {String? category}) {
    cancel(key);
    _timers[key] = timer;
    if (category != null) {
      _categories.putIfAbsent(category, () => {}).add(key);
    }
  }
  
  // 取消指定定时器
  void cancel(String key) {
    final timer = _timers.remove(key);
    if (timer?.isActive ?? false) timer!.cancel();
    
    for (final category in _categories.keys) {
      if (_categories[category]?.remove(key) ?? false) {
        if (_categories[category]?.isEmpty ?? false) {
          _categories.remove(category);
        }
        break;
      }
    }
  }
  
  // 取消所有定时器
  void cancelAll() {
    for (final timer in _timers.values) {
      if (timer.isActive) timer.cancel();
    }
    _timers.clear();
    _categories.clear();
  }
}

// 广告管理类，负责调度与显示
class AdManager with ChangeNotifier {
  // 文字广告字体大小 - 手机端
  static const double TEXT_AD_FONT_SIZE_MOBILE = 15.0;
  // 文字广告字体大小 - 电视端
  static const double TEXT_AD_FONT_SIZE_TV = 22.0;
  // 文字广告循环次数
  static const int TEXT_AD_REPETITIONS = 2;
  // 文字广告滚动速度（像素/秒）
  static const double TEXT_AD_SCROLL_VELOCITY = 38.0;
  // 文字广告距顶部距离
  static const double TEXT_AD_TOP_POSITION = 10.0;
  // 最小重新调度间隔（毫秒）
  static const int MIN_RESCHEDULE_INTERVAL_MS = 2000;
  // 频道切换延迟（毫秒）
  static const int CHANNEL_CHANGE_DELAY_MS = 500;
  // 默认图片广告时长（秒）
  static const int DEFAULT_IMAGE_AD_DURATION = 8;
  // 默认文字广告延迟（秒）
  static const int DEFAULT_TEXT_AD_DELAY = 10;
  // 默认图片广告延迟（秒）
  static const int DEFAULT_IMAGE_AD_DELAY = 20;
  // 视频广告超时时间（秒）
  static const int VIDEO_AD_TIMEOUT_SECONDS = 36;
  // 图片预加载超时时间（秒）
  static const int IMAGE_PRELOAD_TIMEOUT_SECONDS = 5;
  // 最大并发图片加载数
  static const int MAX_CONCURRENT_IMAGE_LOADS = 2;
  // 广告弹窗圆角
  static const double BORDER_RADIUS = 12.0;
  // 标题栏高度
  static const double TITLE_HEIGHT = 32.0;
  // 图片最小宽度
  static const double MIN_IMAGE_WIDTH = 200.0;
  // 图片最小高度
  static const double MIN_IMAGE_HEIGHT = 150.0;

  // 缓存广告数据
  AdData? _adData;
  // 记录广告展示次数
  Map<String, int> _adShownCounts = {};
  // 当前显示的广告类型
  AdType _currentShowingAdType = AdType.none;
  // 广告类型触发状态
  final Map<AdType, bool> _triggeredAdTypes = {
    AdType.text: false,
    AdType.image: false,
    AdType.video: false,
  };
  // 当前文字广告
  AdItem? _currentTextAd;
  // 当前图片广告
  AdItem? _currentImageAd;
  // 当前视频广告
  AdItem? _currentVideoAd;
  // 当前图片广告尺寸
  Size? _currentImageAdSize;
  // 上次频道ID
  String? _lastChannelId;
  // 定时器管理器
  final _timerManager = _TimerManager();
  // 广告最后调度时间
  final Map<String, DateTime> _lastAdScheduleTimes = {};
  // 视频广告播放控制器
  BetterPlayerController? _adController;
  // 图片广告剩余时间
  int _imageAdRemainingSeconds = 0;
  // 图片广告倒计时通知器
  final ValueNotifier<int> imageAdCountdownNotifier = ValueNotifier<int>(0);
  // 广告数据加载状态
  bool _isLoadingAdData = false;
  // 广告数据加载完成器
  Completer<bool>? _adDataLoadedCompleter;
  // 屏幕宽度
  double _screenWidth = 0;
  // 屏幕高度
  double _screenHeight = 0;
  // 是否横屏
  bool _isLandscape = false;
  // 动画同步提供者
  TickerProvider? _vsyncProvider;
  // 已调度广告的频道
  Map<String, bool> _adScheduledChannels = {};
  // 当前会话已投放广告的频道
  Set<String> _advertisedChannels = {};
  // 视频播放状态
  bool _videoStartedPlaying = false;
  // 待调度广告标志
  bool _pendingAdSchedule = false;
  // 图片尺寸缓存
  final _imageCache = _SizedImageCache(maxSize: 30);
  // 有效广告列表缓存
  final Map<AdType, List<AdItem>> _validAdsCache = {};
  // 当前正在加载的图片数量
  int _currentImageLoadCount = 0;

  AdManager() {
    _init();
  }

  // 初始化广告管理器
  Future<void> _init() async {
    _adShownCounts = {};
    _adScheduledChannels = {};
    _advertisedChannels = {};
    _videoStartedPlaying = false;
    _pendingAdSchedule = false;
    await loadAdData();
  }

  // 更新屏幕信息并触发UI更新
  void updateScreenInfo(double width, double height, bool isLandscape, TickerProvider vsync) {
    bool needsUpdate = _screenWidth != width || _screenHeight != height || 
                      _isLandscape != isLandscape || _vsyncProvider != vsync;
    if (needsUpdate) {
      _screenWidth = width;
      _screenHeight = height;
      _isLandscape = isLandscape;
      _vsyncProvider = vsync;
      LogUtil.i('更新屏幕信息: 宽=$width, 高=$height, 横屏=$isLandscape');
      if (_isShowingAnyAd()) notifyListeners();
    }
  }
  
  // 检查是否有广告正在显示
  bool _isShowingAnyAd() => _currentShowingAdType != AdType.none;
  
  // 检查指定类型广告是否正在显示
  bool _isShowingAdType(AdType adType) => _currentShowingAdType == adType;
  
  // 设置当前显示的广告类型
  void _setShowingAdType(AdType? adType) {
    final type = adType ?? AdType.none;
    if (_currentShowingAdType != type) {
      _currentShowingAdType = type;
      notifyListeners();
    }
  }
  
  // 检查广告类型是否已触发
  bool _isAdTypeTriggered(AdType adType) => _triggeredAdTypes[adType] ?? false;
  
  // 设置广告类型触发状态
  void _setAdTypeTriggered(AdType adType, bool value) {
    _triggeredAdTypes[adType] = value;
    if (!value) {
      _validAdsCache.remove(adType);
    }
  }
  
  // 处理频道切换
  void onChannelChanged(String channelId) {
    if (_lastChannelId == channelId) {
      LogUtil.i('频道ID未变化，跳过: $channelId');
      return;
    }
    _lastChannelId = channelId;
    _timerManager.cancelAll();
    _resetTriggerFlags();
    _videoStartedPlaying = false;
    _pendingAdSchedule = true;
    if (_isShowingAnyAd()) _stopAllDisplayingAds();
    _adScheduledChannels[channelId] = false;
    LogUtil.i('频道切换至 $channelId，待视频播放后调度广告');
  }
  
  // 重置广告触发标志
  void _resetTriggerFlags() {
    for (var type in AdType.values) {
      if (type != AdType.none) _triggeredAdTypes[type] = false;
    }
    _validAdsCache.clear();
  }
  
  // 通知视频开始播放并调度广告
  void onVideoStartPlaying() {
    if (_lastChannelId == null) return;
    if (!_shouldScheduleAdsForChannel(_lastChannelId!)) return;
    if (!_videoStartedPlaying && _pendingAdSchedule) {
      _videoStartedPlaying = true;
      LogUtil.i('视频开始播放，调度广告');
      if (Config.adOn && _adData != null) {
        _timerManager.add(
          'channel_change_delay',
          Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
            if (_lastChannelId != null) {
              _advertisedChannels.add(_lastChannelId!);
              _scheduleAdsForNewChannel();
            }
          }),
          category: 'channel_timers'
        );
      }
      _pendingAdSchedule = false;
    }
  }
  
  // 判断是否需要为频道调度广告
  bool _shouldScheduleAdsForChannel(String channelId) {
    if (_adScheduledChannels[channelId] == true) {
      LogUtil.i('频道 $channelId 已调度广告，跳过');
      return false;
    }
    _adScheduledChannels[channelId] = true;
    if (_advertisedChannels.contains(channelId)) {
      LogUtil.i('频道 $channelId 已投放广告，跳过');
      return false;
    }
    return true;
  }
  
  // 停止所有正在显示的广告
  void _stopAllDisplayingAds() {
    if (_currentShowingAdType != AdType.none) {
      switch (_currentShowingAdType) {
        case AdType.text:
          _currentTextAd = null;
          break;
        case AdType.image:
          _currentImageAd = null;
          _currentImageAdSize = null;
          _imageAdRemainingSeconds = 0;
          imageAdCountdownNotifier.value = 0;
          break;
        case AdType.video:
          _cleanupAdController();
          _currentVideoAd = null;
          break;
        case AdType.none:
          break;
      }
      _setShowingAdType(AdType.none);
    }
  }
  
  // 为新频道调度广告
  void _scheduleAdsForNewChannel() {
    if (_adData == null || _lastChannelId == null) return;
    AdItem? nextVideoAd = !_isAdTypeTriggered(AdType.video) ? _selectNextAd(AdType.video) : null;
    AdItem? nextImageAd = !_isAdTypeTriggered(AdType.image) ? _selectNextAd(AdType.image) : null;
    AdItem? nextTextAd = !_isAdTypeTriggered(AdType.text) ? _selectNextAd(AdType.text) : null;
    LogUtil.i('为频道 $_lastChannelId 安排广告: 视频=${nextVideoAd != null}, 图片=${nextImageAd != null}, 文字=${nextTextAd != null}');
    
    if (nextVideoAd != null) {
      LogUtil.i('检测到视频广告，等待外部触发');
    } else if (nextImageAd != null) {
      LogUtil.i('无视频广告，调度图片广告');
      _scheduleAdByType(AdType.image);
    } else if (nextTextAd != null) {
      LogUtil.i('无图片广告，调度文字广告');
      _scheduleAdByType(AdType.text);
    } else {
      LogUtil.i('无可用广告');
    }
  }
  
  // 调度文字广告
  void _scheduleTextAd() => _scheduleAdByType(AdType.text);

  // 调度图片广告
  void _scheduleImageAd() => _scheduleAdByType(AdType.image);
  
  // 统一调度广告类型
  void _scheduleAdByType(AdType adType) {
    if (!Config.adOn || adType == AdType.none) return;
    
    if (_isAdTypeTriggered(adType)) {
      LogUtil.i('${adType.displayName}已触发，跳过');
      return;
    }
    
    if (_shouldSkipDueToOtherAds(adType)) {
      LogUtil.i('其他广告显示中，等待后调度${adType.displayName}');
      return;
    }
    
    if (adType == AdType.image && _isAdTypeTriggered(AdType.video)) {
      LogUtil.i('视频广告已播放，跳过图片广告');
      return;
    }
    
    if (_isRescheduleTooFrequent(adType.stringValue)) {
      LogUtil.i('${adType.displayName}调度频繁，间隔不足 $MIN_RESCHEDULE_INTERVAL_MS ms');
      return;
    }
    
    final nextAd = _selectNextAd(adType);
    if (nextAd == null) {
      LogUtil.i('无可用${adType.displayName}');
      _tryScheduleAlternativeAd(adType);
      return;
    }
    
    _lastAdScheduleTimes[adType.stringValue] = DateTime.now();
    final delaySeconds = nextAd.displayDelaySeconds ?? adType.defaultDelay;
    LogUtil.i('调度${adType.displayName} ${nextAd.id}，延迟 $delaySeconds 秒');
    final timerId = '${adType.stringValue}_${nextAd.id}_${DateTime.now().millisecondsSinceEpoch}';
    
    if (adType == AdType.image) {
      _scheduleImageAdWithPreload(nextAd, timerId, delaySeconds);
    } else {
      _scheduleAdTimer(adType, nextAd, timerId, delaySeconds, null);
    }
  }
  
  // 检查是否因其他广告跳过调度
  bool _shouldSkipDueToOtherAds(AdType adType) {
    if (_isShowingAdType(AdType.video)) return true;
    if (adType == AdType.text && _isShowingAdType(AdType.image)) return true;
    if (adType == AdType.image && _isShowingAdType(AdType.text)) return true;
    return false;
  }
  
  // 检查调度是否过于频繁
  bool _isRescheduleTooFrequent(String adTypeStr) {
    final now = DateTime.now();
    return _lastAdScheduleTimes.containsKey(adTypeStr) && 
           now.difference(_lastAdScheduleTimes[adTypeStr]!).inMilliseconds < MIN_RESCHEDULE_INTERVAL_MS;
  }
  
  // 调度图片广告并预加载
  void _scheduleImageAdWithPreload(AdItem nextAd, String timerId, int delaySeconds) {
    if (nextAd.url != null && _imageCache.containsKey(nextAd.url!)) {
      LogUtil.i('使用缓存图片尺寸: ${nextAd.url}');
      _scheduleAdTimer(AdType.image, nextAd, timerId, delaySeconds, _imageCache.get(nextAd.url!));
      return;
    }
    
    if (_currentImageLoadCount >= MAX_CONCURRENT_IMAGE_LOADS) {
      LogUtil.i('图片加载达到并发限制，稍后重试');
      _timerManager.add(
        'retry_image_load_${nextAd.id}',
        Timer(Duration(seconds: 1), () {
          _scheduleImageAdWithPreload(nextAd, timerId, delaySeconds);
        }),
        category: 'image_load_retry'
      );
      return;
    }
    
    LogUtil.i('预加载图片广告: ${nextAd.url}');
    _currentImageLoadCount++;
    _preloadImageAd(nextAd).then((imageSizeOpt) {
      _currentImageLoadCount--;
      if (imageSizeOpt != null) {
        _scheduleAdTimer(AdType.image, nextAd, timerId, delaySeconds, imageSizeOpt);
      } else {
        LogUtil.i('图片加载失败，尝试文字广告');
        _tryScheduleAlternativeAd(AdType.image);
      }
    });
  }

  // 获取指定类型的广告列表
  List<AdItem> _getAdListByType(AdType adType) {
    if (_adData == null) return [];
    switch (adType) {
      case AdType.text: return _adData!.textAds;
      case AdType.image: return _adData!.imageAds;
      case AdType.video: return _adData!.videoAds;
      case AdType.none: return [];
    }
  }

  // 尝试调度替代广告
  void _tryScheduleAlternativeAd(AdType failedAdType) {
    if (failedAdType == AdType.text && !_isAdTypeTriggered(AdType.image) && 
        !_isShowingAdType(AdType.image) && !_isAdTypeTriggered(AdType.video)) {
      LogUtil.i('无文字广告，尝试图片广告');
      _scheduleAdByType(AdType.image);
    } else if (failedAdType == AdType.image && !_isAdTypeTriggered(AdType.text) && 
               !_isShowingAdType(AdType.text)) {
      LogUtil.i('无图片广告，尝试文字广告');
      _scheduleAdByType(AdType.text);
    } else {
      LogUtil.i('无可替代广告，当前频道无广告');
    }
  }

  // 设置广告显示定时器
  void _scheduleAdTimer(AdType adType, AdItem nextAd, String timerId, int delaySeconds, [Size? imageSize]) {
    _timerManager.add(timerId, Timer(Duration(seconds: delaySeconds), () {
      if (!_canShowAdAfterDelay(adType)) {
        LogUtil.i('条件变化，取消显示${adType.displayName}');
        return;
      }
      if (_isShowingAnyAd()) {
        LogUtil.i('其他广告显示中，等待后显示${adType.displayName}');
        _createAdWaitingTimer(adType, nextAd, timerId, imageSize);
        return;
      }
      _showAd(adType, nextAd, imageSize);
    }), category: 'ad_schedule');
  }
  
  // 检查延迟后是否可显示广告
  bool _canShowAdAfterDelay(AdType adType) {
    if (!Config.adOn) return false;
    if (_isAdTypeTriggered(adType)) return false;
    if (adType == AdType.image && _isAdTypeTriggered(AdType.video)) return false;
    return true;
  }
  
  // 创建广告等待定时器
  void _createAdWaitingTimer(AdType adType, AdItem ad, String timerId, [Size? imageSize]) {
    final waitTimerId = 'wait_$timerId';
    _timerManager.add(waitTimerId, Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingAnyAd()) {
        timer.cancel();
        _timerManager.cancel(waitTimerId);
        if (!_canShowAdAfterDelay(adType)) {
          LogUtil.i('等待期间条件变化，取消${adType.displayName}');
          return;
        }
        _showAd(adType, ad, imageSize);
      }
    }), category: 'ad_waiting');
  }
  
  // 显示广告
  void _showAd(AdType adType, AdItem ad, [Size? imageSize]) {
    _incrementAdShownCount(ad.id);
    _setAdTypeTriggered(adType, true);
    
    switch (adType) {
      case AdType.text:
        _currentTextAd = ad;
        LogUtil.i('显示文字广告 ${ad.id}, 次数: ${_adShownCounts[ad.id]}/${ad.displayCount}');
        break;
      case AdType.image:
        if (imageSize == null) {
          LogUtil.e('图片广告缺少尺寸信息');
          _tryScheduleAlternativeAd(AdType.image);
          return;
        }
        _currentImageAd = ad;
        _currentImageAdSize = imageSize;
        _imageAdRemainingSeconds = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
        LogUtil.i('显示图片广告 ${ad.id}, 次数: ${_adShownCounts[ad.id]}/${ad.displayCount}');
        _startImageAdCountdown(ad);
        break;
      case AdType.video:
        _currentVideoAd = ad;
        LogUtil.i('显示视频广告 ${ad.id}, 次数: ${_adShownCounts[ad.id]}/${ad.displayCount}');
        break;
      case AdType.none:
        return;
    }
    
    _setShowingAdType(adType);
  }

  // 更新广告展示计数
  void _incrementAdShownCount(String adId) {
    AdCountManager.incrementAdCount(adId, _adShownCounts);
  }

  // 启动图片广告倒计时
  void _startImageAdCountdown(AdItem ad) {
    final duration = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    _imageAdRemainingSeconds = duration;
    imageAdCountdownNotifier.value = duration;
    final countdownTimerId = 'countdown_${ad.id}_${DateTime.now().millisecondsSinceEpoch}';
    _timerManager.add(countdownTimerId, Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_imageAdRemainingSeconds <= 1) {
        timer.cancel();
        _timerManager.cancel(countdownTimerId);
        _setShowingAdType(AdType.none);
        _currentImageAd = null;
        _currentImageAdSize = null;
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        if (!_isAdTypeTriggered(AdType.text) && _adData != null) {
          LogUtil.i('图片广告结束，调度文字广告');
          _scheduleTextAd();
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    }), category: 'ad_countdown');
  }

  // 选择下一个可用广告
  AdItem? _selectNextAd(AdType adType) {
    if (!Config.adOn || _adData == null) return null;
    
    if (!_validAdsCache.containsKey(adType)) {
      final allAds = _getAdListByType(adType);
      _validAdsCache[adType] = allAds.where((ad) => 
        ad.enabled && (_adShownCounts[ad.id] ?? 0) < ad.displayCount
      ).toList();
    }
    
    final validAds = _validAdsCache[adType]!;
    if (validAds.isEmpty) return null;
    
    final selectedAd = validAds[Random().nextInt(validAds.length)];
    
    if ((_adShownCounts[selectedAd.id] ?? 0) >= selectedAd.displayCount) {
      validAds.remove(selectedAd);
      return _selectNextAd(adType);
    }
    
    return selectedAd;
  }

  // 为URL添加时间戳
  String _buildTimestampedUrl(String baseUrl) {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    try {
      final uri = Uri.parse(baseUrl);
      final queryParams = Map<String, String>.from(uri.queryParameters)..['t'] = timestamp;
      return Uri(
        scheme: uri.scheme, 
        host: uri.host, 
        path: uri.path, 
        queryParameters: queryParams, 
        port: uri.port
      ).toString();
    } catch (e) {
      LogUtil.e('URL时间戳添加失败: $e');
      final separator = baseUrl.contains('?') ? '&' : '?';
      return '$baseUrl${separator}t=$timestamp';
    }
  }

  // 加载广告数据
  Future<bool> loadAdData() async {
    if (_isLoadingAdData) {
      return _adDataLoadedCompleter?.future ?? Future.value(false);
    }
    _isLoadingAdData = true;
    _adDataLoadedCompleter = Completer<bool>();
    if (!Config.adOn) {
      LogUtil.i('广告功能关闭，不加载数据');
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
    try {
      _adShownCounts = AdCountManager.loadAdCounts();
      final mainUrl = _buildTimestampedUrl(Config.adApiUrl);
      AdData? adData = await _loadAdDataFromUrl(mainUrl);
      if (adData == null && Config.backupAdApiUrl.isNotEmpty) {
        final backupUrl = _buildTimestampedUrl(Config.backupAdApiUrl);
        LogUtil.i('主API失败，尝试备用API: $backupUrl');
        adData = await _loadAdDataFromUrl(backupUrl);
      }
      if (adData != null && !adData.isEmpty) {
        _adData = adData;
        LogUtil.i('广告数据加载成功: 文字=${adData.textAds.length}, 视频=${adData.videoAds.length}, 图片=${adData.imageAds.length}');
        _checkAndSchedulePendingAds();
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(true);
        return true;
      } else {
        _adData = null;
        LogUtil.e('广告数据加载失败: 数据为空');
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      LogUtil.e('加载广告数据异常: $e');
      _adData = null;
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
  }
  
  // 检查并调度挂起广告
  void _checkAndSchedulePendingAds() {
    if (_lastChannelId != null && 
        _adScheduledChannels[_lastChannelId!] == true && 
        !_advertisedChannels.contains(_lastChannelId!) && 
        _videoStartedPlaying) {
      _scheduleAdsForNewChannel();
      _advertisedChannels.add(_lastChannelId!);
    }
  }

  // 从URL加载广告数据
  Future<AdData?> _loadAdDataFromUrl(String url) async {
    try {
      final response = await HttpUtil().getRequest(url, parseData: (data) {
        if (data is! Map<String, dynamic>) {
          LogUtil.e('广告数据格式错误: $data');
          return null;
        }
        if (data.containsKey('text_ads') || data.containsKey('video_ads') || data.containsKey('image_ads')) {
          return AdData.fromJson(data);
        }
        LogUtil.e('广告数据格式不符合预期');
        return null;
      });
      return response;
    } catch (e) {
      LogUtil.e('加载广告数据失败: $e');
      return null;
    }
  }

  // 异步检查是否需要播放视频广告
  Future<bool> shouldPlayVideoAdAsync() async {
    if (_adData != null || !Config.adOn) return shouldPlayVideoAd();
    if (_isLoadingAdData && _adDataLoadedCompleter != null) {
      await _adDataLoadedCompleter!.future;
      return shouldPlayVideoAd();
    }
    await loadAdData();
    return shouldPlayVideoAd();
  }

  // 判断是否需要播放视频广告
  bool shouldPlayVideoAd() {
    if (!Config.adOn || _adData == null || _lastChannelId == null) return false;
    if (_advertisedChannels.contains(_lastChannelId!)) return false;
    if (_isAdTypeTriggered(AdType.video)) return false;
    if (_isShowingAnyAd()) return false;
    final nextAd = _selectNextAd(AdType.video);
    if (nextAd == null) return false;
    _currentVideoAd = nextAd;
    LogUtil.i('需要播放视频广告: ${nextAd.id}');
    return true;
  }

  // 播放视频广告
  Future<void> playVideoAd() async {
    if (!Config.adOn || _currentVideoAd == null || _lastChannelId == null) return;
    _advertisedChannels.add(_lastChannelId!);
    final videoAd = _currentVideoAd!;
    LogUtil.i('播放视频广告: ${videoAd.url}');
    _setShowingAdType(AdType.video);
    _setAdTypeTriggered(AdType.video, true);
    final adCompletion = Completer<void>();
    try {
      final bool isHls = _isHlsStream(videoAd.url);
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: videoAd.url!, 
        isHls: isHls
      );
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: isHls,
        eventListener: (event) => _videoAdEventListener(event, adCompletion),
      );
      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();
      await adCompletion.future.timeout(
        Duration(seconds: VIDEO_AD_TIMEOUT_SECONDS), 
        onTimeout: () {
          LogUtil.i('广告播放超时');
          _cleanupAdController();
          if (!adCompletion.isCompleted) adCompletion.complete();
        }
      );
    } catch (e) {
      LogUtil.e('视频广告播放失败: $e');
      _cleanupAdController();
      if (!adCompletion.isCompleted) adCompletion.completeError(e);
    } finally {
      _incrementAdShownCount(videoAd.id);
      _setShowingAdType(AdType.none);
      _currentVideoAd = null;
      _videoStartedPlaying = true;
      LogUtil.i('广告播放结束，次数: ${_adShownCounts[videoAd.id]}/${videoAd.displayCount}');
      _setAdTypeTriggered(AdType.text, true);
      _setAdTypeTriggered(AdType.image, true);
    }
  }

  // 监听视频广告播放事件
  void _videoAdEventListener(BetterPlayerEvent event, Completer<void> completer) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      if (!completer.isCompleted) completer.complete();
    }
  }

  // 清理视频广告控制器
  void _cleanupAdController() {
    if (_adController != null) {
      _adController?.dispose();
      _adController = null;
    }
  }
  
  // 清理资源
  void _cleanup({bool preserveTimers = false, bool full = false}) {
    if (_adController != null) {
      _adController?.dispose();
      _adController = null;
    }
    
    _setShowingAdType(AdType.none);
    _currentVideoAd = _currentTextAd = _currentImageAd = null;
    _currentImageAdSize = null;
    _imageAdRemainingSeconds = 0;
    imageAdCountdownNotifier.value = 0;
    
    if (!preserveTimers) {
      _timerManager.cancelAll();
    }
    
    if (full) {
      _adData = null;
      _vsyncProvider = null;
      _adScheduledChannels.clear();
      _advertisedChannels.clear();
      _videoStartedPlaying = false;
      _pendingAdSchedule = false;
      _imageCache.clear();
      _lastAdScheduleTimes.clear();
      _validAdsCache.clear();
      _currentImageLoadCount = 0;
      LogUtil.i('广告管理器资源完全释放');
    }
  }

  // 重置广告状态
  void reset({bool rescheduleAds = true, bool preserveTimers = false}) {
    final currentChannelId = _lastChannelId;
    _cleanup(preserveTimers: preserveTimers);
    
    if (rescheduleAds && currentChannelId != null && _adData != null) {
      if (_videoStartedPlaying) {
        _timerManager.add('reschedule', Timer(
          const Duration(milliseconds: MIN_RESCHEDULE_INTERVAL_MS), 
          () {
            if (_lastChannelId == currentChannelId) _scheduleAdsForNewChannel();
          }
        ), category: 'ad_reschedule');
      } else {
        _pendingAdSchedule = true;
      }
    }
  }

  // 释放所有资源
  @override
  void dispose() {
    _cleanup(full: true);
    super.dispose();
  }

  // 检查是否显示文字广告
  bool getShowTextAd() => _isShowingAdType(AdType.text) && _currentTextAd != null && 
                         _currentTextAd!.content != null && Config.adOn;

  // 检查是否显示图片广告
  bool getShowImageAd() => _isShowingAdType(AdType.image) && _currentImageAd != null && Config.adOn;

  // 获取文字广告内容
  String? getTextAdContent() => _currentTextAd?.content;

  // 获取文字广告链接
  String? getTextAdLink() => _currentTextAd?.link;

  // 获取当前图片广告
  AdItem? getCurrentImageAd() => _isShowingAdType(AdType.image) ? _currentImageAd : null;

  // 获取视频广告控制器
  BetterPlayerController? getAdController() => _adController;

  // 构建文字广告
  Widget buildTextAdWidget(BuildContext context) {
    if (!getShowTextAd() || _currentTextAd?.content == null) return const SizedBox.shrink();
    
    final content = getTextAdContent()!;
    final isTV = context.read<ThemeProvider>().isTV;
    final fontSize = isTV ? TEXT_AD_FONT_SIZE_TV : TEXT_AD_FONT_SIZE_MOBILE;
    
    return Positioned(
      top: TEXT_AD_TOP_POSITION,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => _currentTextAd?.link?.isNotEmpty ?? false ? 
                     handleAdClick(_currentTextAd!.link) : null,
        child: Container(
          width: double.infinity,
          height: fontSize * 1.5,
          color: Colors.black.withOpacity(0.5),
          child: Marquee(
            text: content,
            style: TextStyle(
              color: Colors.white, 
              fontSize: fontSize, 
              shadows: const [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.5, color: Colors.black)]
            ),
            scrollAxis: Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.center,
            velocity: TEXT_AD_SCROLL_VELOCITY,
            blankSpace: _screenWidth,
            startPadding: _screenWidth,
            accelerationDuration: Duration.zero,
            decelerationDuration: Duration.zero,
            accelerationCurve: Curves.linear,
            decelerationCurve: Curves.linear,
            numberOfRounds: TEXT_AD_REPETITIONS,
            pauseAfterRound: Duration.zero,
            showFadingOnlyWhenScrolling: false,
            fadingEdgeStartFraction: 0.0,
            fadingEdgeEndFraction: 0.0,
            startAfter: Duration.zero,
            onDone: () {
              LogUtil.i('文字广告循环完成');
              _currentTextAd = null;
              _setShowingAdType(AdType.none);
            },
          ),
        ),
      ),
    );
  }

  // 构建图片广告Widget
  Widget buildImageAdWidget() {
    if (!getShowImageAd() || _currentImageAd == null || _currentImageAdSize == null) {
      return const SizedBox.shrink();
    }
    final imageAd = _currentImageAd!;
    final imageSize = _currentImageAdSize!;
    final aspectRatio = imageSize.width / imageSize.height;
    double imageWidth = aspectRatio > 1 ? 
                        min(_screenWidth * 0.8, imageSize.width) : 
                        (min(_screenHeight * 0.7, imageSize.height) * aspectRatio);
    double imageHeight = aspectRatio > 1 ? 
                         imageWidth / aspectRatio : 
                         min(_screenHeight * 0.7, imageSize.height);
    imageWidth = max(imageWidth, MIN_IMAGE_WIDTH);
    imageHeight = max(imageHeight, MIN_IMAGE_HEIGHT);
    final popupWidth = imageWidth;
    final popupHeight = TITLE_HEIGHT + imageHeight;
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: popupWidth,
          height: popupHeight,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: BorderRadius.circular(BORDER_RADIUS),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5), 
                spreadRadius: 3, 
                blurRadius: 10, 
                offset: Offset(0, 3)
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: TITLE_HEIGHT,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade800, 
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(BORDER_RADIUS), 
                    topRight: Radius.circular(BORDER_RADIUS)
                  )
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '推广内容', 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    Row(
                      children: [
                        const Text(
                          '广告关闭倒计时: ', 
                          style: TextStyle(color: Colors.white70, fontSize: 14)
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: imageAdCountdownNotifier,
                          builder: (context, remainingSeconds, child) => Text(
                            '$remainingSeconds秒', 
                            style: TextStyle(
                              color: Colors.red, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 14
                            )
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: imageWidth,
                height: imageHeight,
                child: GestureDetector(
                  onTap: () => imageAd.link?.isNotEmpty ?? false ? 
                               handleAdClick(imageAd.link) : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(BORDER_RADIUS), 
                      bottomRight: Radius.circular(BORDER_RADIUS)
                    ),
                    child: Image.network(
                      imageAd.url!,
                      fit: BoxFit.fill,
                      width: imageWidth,
                      height: imageHeight,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[900], 
                        child: Center(
                          child: Text(
                            '广告加载失败', 
                            style: TextStyle(color: Colors.white70, fontSize: 16)
                          )
                        )
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 预加载图片广告并获取尺寸
  Future<Size?> _preloadImageAd(AdItem ad) async {
    if (ad.url == null || ad.url!.isEmpty) return null;
    if (_imageCache.containsKey(ad.url!)) return _imageCache.get(ad.url!);
    
    try {
      final result = await _loadImageWithTimeout(ad.url!, IMAGE_PRELOAD_TIMEOUT_SECONDS);
      if (result != null) {
        _imageCache.set(ad.url!, result);
      }
      return result;
    } catch (e) {
      LogUtil.e('预加载图片异常: $e');
      return null;
    }
  }
  
  // 加载图片并设置超时
  Future<Size?> _loadImageWithTimeout(String url, int timeoutSeconds) {
    final completer = Completer<Size?>();
    final imageProvider = NetworkImage(url);
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    ImageStreamListener? listener;
    
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        LogUtil.i('图片加载超时');
        completer.complete(null);
        if (listener != null) {
          stream.removeListener(listener);
        }
      }
    });
    
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
        LogUtil.i('图片预加载成功: ${size.width}x${size.height}');
        if (!completer.isCompleted) {
          completer.complete(size);
        }
        timer.cancel();
        stream.removeListener(listener!);
      },
      onError: (exception, stackTrace) {
        LogUtil.e('图片加载失败: $exception');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        timer.cancel();
        stream.removeListener(listener!);
      },
    );
    
    stream.addListener(listener);
    return completer.future;
  }

  // 处理广告点击跳转
  Future<void> handleAdClick(String? link) async {
    if (link == null || link.isEmpty) return;
    try {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        LogUtil.i('打开广告链接: $link');
      } else {
        LogUtil.e('无法打开链接: $link');
      }
    } catch (e) {
      LogUtil.e('打开链接出错: $link, 错误: $e');
    }
  }

  // 判断是否为HLS流
  bool _isHlsStream(String? url) => url != null && url.toLowerCase().contains('.m3u8');
}
