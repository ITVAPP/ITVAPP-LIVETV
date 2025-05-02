import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/config.dart';

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

// 定义广告类型枚举
enum AdType { text, image, video, none }

// 广告类型扩展，提供类型相关的辅助方法
extension AdTypeExtension on AdType {
  // 使用静态Map缓存枚举值的字符串表示和配置
  static final Map<AdType, String> _stringValues = {
    AdType.text: 'text',
    AdType.image: 'image',
    AdType.video: 'video',
    AdType.none: 'none',
  };
  
  static final Map<AdType, String> _displayNames = {
    AdType.text: '文字广告',
    AdType.image: '图片广告',
    AdType.video: '视频广告',
    AdType.none: '未知广告',
  };
  
  static final Map<AdType, int> _defaultDelays = {
    AdType.text: AdManager.DEFAULT_TEXT_AD_DELAY,
    AdType.image: AdManager.DEFAULT_IMAGE_AD_DELAY,
    AdType.video: 0,
    AdType.none: 0,
  };
  
  String get stringValue => _stringValues[this]!; // 获取广告类型字符串
  String get displayName => _displayNames[this]!; // 获取广告类型展示名称
  int get defaultDelay => _defaultDelays[this]!; // 获取默认延迟时间
}

// 缓存管理类，使用 LinkedHashMap 简化图片尺寸缓存
class _SizedImageCache {
  final int maxSize; // 缓存最大容量
  final LinkedHashMap<String, Size> _cache; // 图片尺寸缓存

  _SizedImageCache({this.maxSize = 30})
      : _cache = LinkedHashMap<String, Size>(
            equals: (a, b) => a == b,
            hashCode: (key) => key.hashCode,
          );

  Size? get(String key) => _cache[key]; // 获取缓存中的图片尺寸
  void set(String key, Size size) { // 缓存图片尺寸，超出容量移除最早项
    if (_cache.length >= maxSize && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = size;
  }
  bool containsKey(String key) => _cache.containsKey(key); // 检查是否包含指定键
  void clear() => _cache.clear(); // 清空缓存
}

// 单个广告项模型
class AdItem {
  final String id; // 广告唯一标识符
  final String? content; // 文字广告内容
  final String? url; // 视频/图片广告URL
  final bool enabled; // 广告启用状态
  final int displayCount; // 最大展示次数
  final int? displayDelaySeconds; // 展示延迟时间（秒）
  final int? durationSeconds; // 图片广告显示时长（秒）
  final String? link; // 点击跳转链接
  final String type; // 广告类型：'text', 'video', 'image'

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
  final List<AdItem> textAds; // 文字广告列表
  final List<AdItem> videoAds; // 视频广告列表
  final List<AdItem> imageAds; // 图片广告列表

  const AdData({
    required this.textAds,
    required this.videoAds,
    required this.imageAds,
  });

  // 解析广告项列表，统一处理逻辑
  static List<AdItem> _parseAdItems(List? adsList, String type, {
    String? idPrefix,
    bool needsContent = false,
    bool needsUrl = false,
  }) {
    if (adsList == null || adsList.isEmpty) return [];
    
    return adsList.map((item) { // 解析单个广告项
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
  factory AdData.fromJson(Map<String, dynamic> json) { // 解析JSON为广告数据
    final data = json;
    return AdData(
      textAds: _parseAdItems(data['text_ads'] as List?, 'text', idPrefix: 'text', needsContent: true),
      videoAds: _parseAdItems(data['video_ads'] as List?, 'video', idPrefix: 'video', needsUrl: true),
      imageAds: _parseAdItems(data['image_ads'] as List?, 'image', idPrefix: 'image', needsUrl: true),
    );
  }
  
  bool get isEmpty => textAds.isEmpty && videoAds.isEmpty && imageAds.isEmpty; // 判断广告数据是否为空
}

// 广告计数管理辅助类
class AdCountManager {
  static Map<String, int> loadAdCounts() => {}; // 加载广告展示次数
  static void saveAdCounts(Map<String, int> counts) { // 保存广告展示次数
    LogUtil.i('广告计数仅保存在内存中，应用重启将重置');
  }
  static void incrementAdCount(String adId, Map<String, int> counts) { // 增加广告展示计数
    counts[adId] = (counts[adId] ?? 0) + 1;
  }
}

// 广告管理类，负责广告调度与显示
class AdManager with ChangeNotifier {
  // 文字广告配置常量
  static const double TEXT_AD_FONT_SIZE = 14.0; // 文字广告字体大小
  static const double TEXT_AD_SCROLL_VELOCITY = 38.0; // 文字广告滚动速度（像素/秒）
  
  // 广告位置常量
  static const double TEXT_AD_TOP_POSITION = 10.0; // 文字广告距顶部距离

  // 时间相关常量
  static const int MIN_RESCHEDULE_INTERVAL_MS = 2000; // 最小重新调度间隔
  static const int CHANNEL_CHANGE_DELAY_MS = 500; // 频道切换后延迟
  static const int DEFAULT_IMAGE_AD_DURATION = 8; // 默认图片广告时长
  static const int DEFAULT_TEXT_AD_DELAY = 10; // 默认文字广告延迟
  static const int DEFAULT_IMAGE_AD_DELAY = 20; // 默认图片广告延迟
  static const int VIDEO_AD_TIMEOUT_SECONDS = 36; // 视频广告超时时间
  static const int IMAGE_PRELOAD_TIMEOUT_SECONDS = 5; // 图片预加载超时时间

  // 广告UI常量
  static const double BORDER_RADIUS = 12.0; // 广告弹窗圆角
  static const double TITLE_HEIGHT = 32.0; // 标题栏高度
  static const double MIN_IMAGE_WIDTH = 200.0; // 图片最小宽度
  static const double MIN_IMAGE_HEIGHT = 150.0; // 图片最小高度

  AdData? _adData; // 存储广告数据
  Map<String, int> _adShownCounts = {}; // 记录广告展示次数
  
  AdType _currentShowingAdType = AdType.none; // 当前显示的广告类型
  
  // 管理广告类型触发状态
  final Map<AdType, bool> _triggeredAdTypes = {
    AdType.text: false,
    AdType.image: false,
    AdType.video: false,
  };
  
  AdItem? _currentTextAd; // 当前文字广告
  AdItem? _currentImageAd; // 当前图片广告
  AdItem? _currentVideoAd; // 当前视频广告
  Size? _currentImageAdSize; // 当前图片广告尺寸
  
  String? _lastChannelId; // 上次频道ID
  
  final Map<String, Timer> _timers = {}; // 定时器容器
  
  final Map<String, DateTime> _lastAdScheduleTimes = {}; // 广告最后调度时间
  
  BetterPlayerController? _adController; // 视频广告播放控制器
  
  int _imageAdRemainingSeconds = 0; // 图片广告剩余时间
  final ValueNotifier<int> imageAdCountdownNotifier = ValueNotifier<int>(0); // 倒计时通知器

  bool _isLoadingAdData = false; // 广告数据加载状态
  Completer<bool>? _adDataLoadedCompleter; // 广告数据加载完成器

  double _screenWidth = 0; // 屏幕宽度
  double _screenHeight = 0; // 屏幕高度
  TickerProvider? _vsyncProvider; // 动画同步提供者
  
  Set<String> _advertisedChannels = {}; // 当前会话已投放广告的频道
  bool _videoStartedPlaying = false; // 视频播放304状态
  bool _pendingAdSchedule = false; // 待调度广告标志
  
  final _imageCache = _SizedImageCache(maxSize: 30); // 图片尺寸缓存
  
  final Random _random = Random(); // 随机数生成器

  AdManager() {
    _init(); // 初始化广告管理器
  }

  // 初始化广告管理器
  Future<void> _init() async { // 初始化广告计数和状态
    _adShownCounts = {};
    _advertisedChannels = {};
    _videoStartedPlaying = false;
    _pendingAdSchedule = false;
    await loadAdData();
  }

  // 更新屏幕信息并触发UI更新
  void updateScreenInfo(double width, double height, bool isLandscape, TickerProvider vsync) { // 更新屏幕尺寸和同步提供者
    bool needsUpdate = _screenWidth != width || _screenHeight != height || 
                      _vsyncProvider != vsync;
    if (needsUpdate) {
      _screenWidth = width;
      _screenHeight = height;
      _vsyncProvider = vsync;
      LogUtil.i('更新屏幕信息: 宽=$width, 高=$height, 横屏=$isLandscape');
      if (_isShowingAnyAd()) notifyListeners();
    }
  }
  
  bool _isShowingAnyAd() => _currentShowingAdType != AdType.none; // 检查是否有广告显示
  bool _isShowingAdType(AdType adType) => _currentShowingAdType == adType; // 检查指定类型广告是否显示
  void _setShowingAdType(AdType? adType) { // 设置当前显示广告类型
    final type = adType ?? AdType.none;
    if (_currentShowingAdType != type) {
      _currentShowingAdType = type;
      notifyListeners();
    }
  }
  bool _isAdTypeTriggered(AdType adType) => _triggeredAdTypes[adType] ?? false; // 检查广告类型是否触发
  void _setAdTypeTriggered(AdType adType, bool value) { // 设置广告类型触发状态
    _triggeredAdTypes[adType] = value;
  }

  // 处理频道切换逻辑
  void onChannelChanged(String channelId) { // 处理频道切换，重置状态
    if (_lastChannelId == channelId) {
      return;
    }
    LogUtil.i('检测到频道切换: $channelId');
    _lastChannelId = channelId;
    _cancelAllTimers();
    _resetTriggerFlags();
    _videoStartedPlaying = false;
    _pendingAdSchedule = true;
    if (_isShowingAnyAd()) _stopAllDisplayingAds();
    _advertisedChannels.remove(channelId);
    LogUtil.i('频道切换至: $channelId，等待视频播放后调度广告');
  }
  
  void _resetTriggerFlags() { // 重置所有广告触发标志
    for (var type in AdType.values) {
      if (type != AdType.none) _triggeredAdTypes[type] = false;
    }
  }
  
  // 通知视频开始播放并调度广告
  void onVideoStartPlaying() { // 视频播放开始后调度广告
    if (_lastChannelId == null || _advertisedChannels.contains(_lastChannelId!)) return;
    
    if (!_videoStartedPlaying && _pendingAdSchedule) {
      _videoStartedPlaying = true;
      LogUtil.i('视频开始播放，调度广告');
      if (Config.adOn && _adData != null) {
        _addTimer(
          'channel_change_delay',
          Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
            if (_lastChannelId != null) {
              _advertisedChannels.add(_lastChannelId!);
              _scheduleAdsForNewChannel();
            }
          })
        );
      }
      _pendingAdSchedule = false;
    }
  }
  
  void _addTimer(String key, Timer timer) { // 添加定时器，覆盖同名定时器
    _cancelTimer(key);
    _timers[key] = timer;
  }
  
  void _cancelTimer(String key) { // 取消指定定时器
    final timer = _timers[key];
    if (timer != null && timer.isActive) {
      timer.cancel();
      _timers.remove(key);
    }
  }
  
  void _cancelAllTimers() { //.ConcurrentModificationError 取消所有定时器
    final timers = List<MapEntry<String, Timer>>.from(_timers.entries);
    for (var entry in timers) {
      if (entry.value.isActive) entry.value.cancel();
    }
    _timers.clear();
  }
  
  void _stopAllDisplayingAds() { // 停止所有正在显示的广告
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
  void _scheduleAdsForNewChannel() { // 为新频道安排广告显示
    if (_adData == null || _lastChannelId == null) return;
    
    final needVideoAd = !_isAdTypeTriggered(AdType.video);
    final needImageAd = !_isAdTypeTriggered(AdType.image);
    final needTextAd = !_isAdTypeTriggered(AdType.text);
    
    AdItem? nextVideoAd = needVideoAd ? _selectNextAd(_adData!.videoAds) : null;
    AdItem? nextImageAd = needImageAd ? _selectNextAd(_adData!.imageAds) : null;
    AdItem? nextTextAd = needTextAd ? _selectNextAd(_adData!.textAds) : null;
    
    final logMsg = StringBuffer('为频道 $_lastChannelId 安排广告: ')
      ..write('视频=${nextVideoAd != null}, ')
      ..write('图片=${nextImageAd != null}, ')
      ..write('文字=${nextTextAd != null}');
    LogUtil.i(logMsg.toString());
    
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
  
  void _scheduleAdByType(AdType adType) { // 按广告类型调度显示
    if (!Config.adOn || _isAdTypeTriggered(adType)) {
      LogUtil.i('${adType.displayName}${Config.adOn ? "已触发" : "功能已关闭"}，跳过');
      return;
    }
    
    if (!_canShowAd(adType)) {
      LogUtil.i('其他广告显示中，等待结束再调度${adType.displayName}');
      return;
    }
    
    final adsList = adType == AdType.text ? _adData!.textAds : 
                   adType == AdType.image ? _adData!.imageAds : [];
    
    final nextAd = _selectNextAd(adsList);
    if (nextAd == null) {
      LogUtil.i('无可用${adType.displayName}');
      _tryScheduleAlternativeAd(adType);
      return;
    }
    
    _lastAdScheduleTimes[adType.stringValue] = DateTime.now();
    final delaySeconds = nextAd.displayDelaySeconds ?? adType.defaultDelay;
    LogUtil.i('调度${adType.displayName} ${nextAd.id}，延迟 $delaySeconds 秒');
    
    final timerId = StringBuffer()
      ..write(adType.stringValue)
      ..write('_')
      ..write(nextAd.id)
      ..write('_')
      ..write(DateTime.now().millisecondsSinceEpoch)
      .toString();
    
    if (adType == AdType.image) {
      final url = nextAd.url;
      if (url != null && _imageCache.containsKey(url)) {
        LogUtil.i('使用缓存图片尺寸: $url');
        _scheduleAdTimer(adType, nextAd, timerId, delaySeconds, _imageCache.get(url));
      } else {
        LogUtil.i('预加载图片广告: $url');
        _preloadImageAd(nextAd).then((imageSizeOpt) {
          if (imageSizeOpt != null) {
            _scheduleAdTimer(adType, nextAd, timerId, delaySeconds, imageSizeOpt);
          } else {
            LogUtil.i('图片加载失败，尝试文字广告');
            _tryScheduleAlternativeAd(adType);
          }
        });
      }
    } else {
      _scheduleAdTimer(adType, nextAd, timerId, delaySeconds, null);
    }
  }
  
  bool _canShowAd(AdType adType) { // 检查是否可以显示指定类型广告
    if (!Config.adOn || _isAdTypeTriggered(adType)) return false;
    if (_isShowingAdType(AdType.video)) return false;
    
    switch (adType) {
      case AdType.text:
        return !_isShowingAdType(AdType.image);
      case AdType.image:
        return !_isShowingAdType(AdType.text) && !_isAdTypeTriggered(AdType.video);
      case AdType.video:
        return true;
      case AdType.none:
        return false;
    }
  }
  
  void _tryScheduleAlternativeAd(AdType failedAdType) { // 尝试调度替代广告类型
    if (failedAdType == AdType.text && 
        !_isAdTypeTriggered(AdType.image) && 
        !_isShowingAdType(AdType.image) && 
        !_isAdTypeTriggered(AdType.video)) {
      LogUtil.i('无文字广告，尝试图片广告');
      _scheduleAdByType(AdType.image);
    } else if (failedAdType == AdType.image && 
               !_isAdTypeTriggered(AdType.text) && 
               !_isShowingAdType(AdType.text)) {
      LogUtil.i('无图片广告，尝试文字广告');
      _scheduleAdByType(AdType.text);
    } else {
      LogUtil.i('无可替代广告，当前频道无广告');
    }
  }
  
  void _scheduleAdTimer(AdType adType, AdItem nextAd, String timerId, int delaySeconds, [Size? imageSize]) { // 设置广告显示定时器
    _addTimer(timerId, Timer(Duration(seconds: delaySeconds), () {
      if (!_canShowAd(adType)) {
        LogUtil.i('条件变化，取消显示${adType.displayName}');
        return;
      }
      if (_isShowingAnyAd()) {
        LogUtil.i('其他广告显示中，等待后显示${adType.displayName}');
        final waitTimerId = 'wait_$timerId';
        _addTimer(waitTimerId, Timer.periodic(Duration(seconds: 1), (timer) {
          if (!_isShowingAnyAd()) {
            timer.cancel();
            _cancelTimer(waitTimerId);
            if (!_canShowAd(adType)) {
              LogUtil.i('等待期间条件变化，取消${adType.displayName}');
              return;
            }
            _showAdByType(adType, nextAd, imageSize);
          }
        }));
        return;
      }
      _showAdByType(adType, nextAd, imageSize);
    }));
  }
  
  void _showAdByType(AdType adType, AdItem ad, [Size? imageSize]) { // 根据类型显示广告
    switch (adType) {
      case AdType.text: 
        _showTextAd(ad); 
        break;
      case AdType.image:
        if (imageSize != null) {
          _showImageAd(ad, imageSize);
        } else {
          LogUtil.e('图片广告缺少尺寸信息');
          _tryScheduleAlternativeAd(adType);
        }
        break;
      case AdType.video:
        LogUtil.i('视频广告由外部触发');
        break;
      case AdType.none:
        LogUtil.e('无效广告类型');
        break;
    }
  }
  
  void _showTextAd(AdItem ad) { // 显示文字广告并更新计数
    _currentTextAd = ad;
    _setShowingAdType(AdType.text);
    _incrementAdShownCount(ad.id);
    _setAdTypeTriggered(AdType.text, true);
    LogUtil.i('显示文字广告 ${ad.id}, 次数: ${_adShownCounts[ad.id]}/${ad.displayCount}');
  }

  void _incrementAdShownCount(String adId) { // 更新广告展示计数
    _adShownCounts[adId] = (_adShownCounts[adId] ?? 0) + 1;
    AdCountManager.incrementAdCount(adId, _adShownCounts);
  }

  void _showImageAd(AdItem ad, Size preloadedSize) { // 显示图片广告并启动倒计时
    _currentImageAd = ad;
    _currentImageAdSize = preloadedSize;
    _setShowingAdType(AdType.image);
    _incrementAdShownCount(ad.id);
    _setAdTypeTriggered(AdType.image, true);
    _imageAdRemainingSeconds = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
    LogUtil.i('显示图片广告 ${ad.id}, 次数: ${_adShownCounts[ad.id]}/${ad.displayCount}');
    _startImageAdCountdown(ad);
  }

  void _startImageAdCountdown(AdItem ad) { // 启动图片广告倒计时
    final duration = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    _imageAdRemainingSeconds = duration;
    imageAdCountdownNotifier.value = duration;
    
    final countdownTimerId = StringBuffer('countdown_')
      ..write(ad.id)
      ..write('_')
      ..write(DateTime.now().millisecondsSinceEpoch)
      .toString();
      
    _addTimer(countdownTimerId, Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_imageAdRemainingSeconds <= 1) {
        timer.cancel();
        _cancelTimer(countdownTimerId);
        _setShowingAdType(AdType.none);
        _currentImageAd = null;
        _currentImageAdSize = null;
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        if (!_isAdTypeTriggered(AdType.text) && _adData != null) {
          LogUtil.i('图片广告结束，调度文字广告');
          _scheduleAdByType(AdType.text);
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    }));
  }

  AdItem? _selectNextAd(List<AdItem> candidates) { // 随机选择下一个有效广告
    if (candidates.isEmpty || !Config.adOn) return null;
    
    final validAds = <AdItem>[];
    for (final ad in candidates) {
      if (ad.enabled && (_adShownCounts[ad.id] ?? 0) < ad.displayCount) {
        validAds.add(ad);
      }
    }
    
    if (validAds.isEmpty) return null;
    return validAds.length == 1 ? validAds.first : 
        validAds[_random.nextInt(validAds.length)];
  }

  String _buildTimestampedUrl(String baseUrl) { // 为URL添加时间戳
    final now = DateTime.now();
    final timestampBuffer = StringBuffer()
      ..write(now.year)
      ..write(now.month.toString().padLeft(2, '0'))
      ..write(now.day.toString().padLeft(2, '0'))
      ..write(now.hour.toString().padLeft(2, '0'))
      ..write(now.minute.toString().padLeft(2, '0'))
      ..write(now.second.toString().padLeft(2, '0'));
    final timestamp = timestampBuffer.toString();
    
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

  Future<bool> loadAdData() async { // 加载广告数据，支持主备API
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
      LogUtil.i('加载广告数据: $mainUrl');
      AdData? adData = await _loadAdDataFromUrl(mainUrl);
      if (adData == null && Config.backupAdApiUrl.isNotEmpty) {
        final backupUrl = _buildTimestampedUrl(Config.backupAdApiUrl);
        LogUtil.i('主API失败，尝试备用API: $backupUrl');
        adData = await _loadAdDataFromUrl(backupUrl);
      }
      if (adData != null && !adData.isEmpty) {
        _adData = adData;
        final logMsg = StringBuffer('广告数据加载成功: ')
          ..write('文字=${adData.textAds.length}, ')
          ..write('视频=${adData.videoAds.length}, ')
          ..write('图片=${adData.imageAds.length}');
        LogUtil.i(logMsg.toString());
        
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
  
  void _checkAndSchedulePendingAds() { // 检查并调度挂起的广告
    if (_lastChannelId != null && 
        !_advertisedChannels.contains(_lastChannelId!) && 
        _videoStartedPlaying) {
      _scheduleAdsForNewChannel();
      _advertisedChannels.add(_lastChannelId!);
    }
  }

  Future<AdData?> _loadAdDataFromUrl(String url) async { // 从指定URL加载广告数据
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

  Future<bool> shouldPlayVideoAdAsync() async { // 异步检查是否需要播放视频广告
    if (_adData != null || !Config.adOn) return shouldPlayVideoAd();
    if (_isLoadingAdData && _adDataLoadedCompleter != null) {
      await _adDataLoadedCompleter!.future;
      return shouldPlayVideoAd();
    }
    await loadAdData();
    return shouldPlayVideoAd();
  }

  bool shouldPlayVideoAd() { // 判断是否需要播放视频广告
    if (!Config.adOn || 
        _adData == null || 
        _lastChannelId == null || 
        _advertisedChannels.contains(_lastChannelId!) || 
        _isAdTypeTriggered(AdType.video) || 
        _isShowingAnyAd()) {
      return false;
    }
    
    final nextAd = _selectNextAd(_adData!.videoAds);
    if (nextAd == null) return false;
    
    _currentVideoAd = nextAd;
    LogUtil.i('需要播放视频广告: ${nextAd.id}');
    return true;
  }

  Future<void> playVideoAd() async { // 播放视频广告并管理生命周期
    if (!Config.adOn || _currentVideoAd == null || _lastChannelId == null) return;
    
    _advertisedChannels.add(_lastChannelId!);
    final videoAd = _currentVideoAd!;
    LogUtil.i('播放视频广告: ${videoAd.url}');
    _setShowingAdType(AdType.video);
    _setAdTypeTriggered(AdType.video, true);
    
    final adCompletion = Completer<void>();
    try {
      final url = videoAd.url!;
      final bool isHls = _isHlsStream(url);
      
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: url, 
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

  void _videoAdEventListener(BetterPlayerEvent event, Completer<void> completer) { // 监听视频广告播放事件
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      if (!completer.isCompleted) completer.complete();
    }
  }

  void _cleanupAdController() { // 清理视频广告控制器资源
    if (_adController != null) {
      _adController?.dispose();
      _adController = null;
    }
  }

  void reset({bool rescheduleAds = true, bool preserveTimers = false}) { // 重置广告状态
    final currentChannelId = _lastChannelId;
    _cleanupAdController();
    _setShowingAdType(AdType.none);
    _currentVideoAd = null;
    _currentTextAd = null;
    _currentImageAd = null;
    _currentImageAdSize = null;
    _imageAdRemainingSeconds = 0;
    imageAdCountdownNotifier.value = 0;
    if (!preserveTimers) _cancelAllTimers();
    LogUtil.i('广告管理器重置，重新调度: $rescheduleAds, 保留定时器: $preserveTimers');
    if (rescheduleAds && currentChannelId != null && _adData != null && _videoStartedPlaying) {
      _addTimer('reschedule', Timer(
        const Duration(milliseconds: MIN_RESCHEDULE_INTERVAL_MS), 
        () {
          if (_lastChannelId == currentChannelId) _scheduleAdsForNewChannel();
        }
      ));
    } else if (rescheduleAds && !_videoStartedPlaying) {
      _pendingAdSchedule = true;
    }
  }

  @override
  void dispose() { // 释放广告管理器所有资源
    _cleanupAdController();
    _cancelAllTimers();
    _setShowingAdType(AdType.none);
    _currentTextAd = null;
    _currentImageAd = null;
    _currentVideoAd = null;
    _currentImageAdSize = null;
    _adData = null;
    _vsyncProvider = null;
    _advertisedChannels.clear();
    _videoStartedPlaying = false;
    _pendingAdSchedule = false;
    _imageCache.clear();
    LogUtil.i('广告管理器资源释放');
    super.dispose();
  }

  String? getTextAdContent() => _currentTextAd?.content; // 获取当前文字广告内容
  String? getTextAdLink() => _currentTextAd?.link; // 获取当前文字广告链接
  AdItem? getCurrentImageAd() => _isShowingAdType(AdType.image) ? _currentImageAd : null; // 获取当前图片广告
  BetterPlayerController? getAdController() => _adController; // 获取视频广告控制器

  // 构建文字广告Widget
  Widget buildTextAdWidget() { // 构建滚动文字广告组件
    if (!_isShowingAdType(AdType.text) || _currentTextAd?.content == null || !Config.adOn) return const SizedBox.shrink();
    final content = getTextAdContent()!;
    return Positioned(
      top: TEXT_AD_TOP_POSITION,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => _currentTextAd?.link?.isNotEmpty ?? false ? 
                     handleAdClick(_currentTextAd!.link) : null,
        child: Container(
          width: double.infinity,
          height: TEXT_AD_FONT_SIZE * 1.5,
          color: Colors.black.withOpacity(0.5),
          child: Marquee(
            text: content,
            style: const TextStyle(
              color: Colors.white, 
              fontSize: TEXT_AD_FONT_SIZE, 
              shadows: [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.5, color: Colors.black)]
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
            numberOfRounds: 2,
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
  Widget buildImageAdWidget() { // 构建图片广告弹窗组件
    if (!_isShowingAdType(AdType.image) || _currentImageAd == null || _currentImageAdSize == null || !Config.adOn) {
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

  Future<Size?> _preloadImageAd(AdItem ad) async { // 预加载图片广告并缓存尺寸
    final url = ad.url;
    if (url == null || url.isEmpty) return null;
    if (_imageCache.containsKey(url)) return _imageCache.get(url);
    
    try {
      final Completer<Size?> completer = Completer();
      final imageProvider = NetworkImage(url);
      final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
      ImageStreamListener? listener;
      Timer? timeoutTimer;
      
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
          LogUtil.i('图片预加载成功: ${size.width}x${size.height}');
          completer.complete(size);
          if (timeoutTimer?.isActive ?? false) timeoutTimer!.cancel();
          stream.removeListener(listener!);
        },
        onError: (exception, stackTrace) {
          LogUtil.e('图片加载失败: $exception');
          completer.complete(null);
          if (timeoutTimer?.isActive ?? false) timeoutTimer!.cancel();
          stream.removeListener(listener!);
        },
      );
      
      stream.addListener(listener);
      timeoutTimer = Timer(Duration(seconds: IMAGE_PRELOAD_TIMEOUT_SECONDS), () {
        if (!completer.isCompleted) {
          LogUtil.i('图片加载超时');
          completer.complete(null);
          stream.removeListener(listener!);
        }
      });
      
      final result = await completer.future;
      if (result != null) _imageCache.set(url, result);
      return result;
    } catch (e) {
      LogUtil.e('预加载图片异常: $e');
      return null;
    }
  }

  Future<void> handleAdClick(String? link) async { // 处理广告点击跳转
    if (link == null || link.isEmpty) return;
    try {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        LogUtil.e('无法打开链接: $link');
      }
    } catch (e) {
      LogUtil.e('打开链接出错: $link, 错误: $e');
    }
  }

  bool _isHlsStream(String? url) => url != null && url.toLowerCase().contains('.m3u8'); // 判断是否为HLS视频流
}
