import 'dart:async';
import 'dart:convert';
import 'dart:math';
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

// 广告类型参数辅助类
class _AdTypeParams {
  final List<AdItem> adsList;
  final String logPrefix;
  final bool hasTriggered;
  final int defaultDelay;
  _AdTypeParams({required this.adsList, required this.logPrefix, required this.hasTriggered, required this.defaultDelay});
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
    if (adsList == null || adsList.isEmpty) return []; // 空列表返回空结果
    
    return adsList.map((item) {
      // 验证必要字段并跳过无效项
      if (needsContent && (item['content'] == null || item['content'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少必要的 content 字段，跳过此项');
        return null;
      }
      
      if (needsUrl && (item['url'] == null || item['url'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少必要的 url 字段，跳过此项');
        return null;
      }
      
      final adId = item['id'] ?? '${idPrefix ?? type}_${DateTime.now().millisecondsSinceEpoch}'; // 生成唯一ID
      
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
    }).whereType<AdItem>().toList(); // 过滤无效项
  }

  factory AdData.fromJson(Map<String, dynamic> json) {
    // 从JSON解析广告数据
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
  // 获取广告展示次数，仅返回内存数据
  static Future<Map<String, int>> loadAdCounts() async => {};

  // 保存广告展示次数，仅更新内存
  static Future<void> saveAdCounts(Map<String, int> counts) async {
    LogUtil.i('广告计数仅保存在内存中，应用重启将重置');
  }

  // 增加广告展示计数
  static Future<void> incrementAdCount(String adId, Map<String, int> counts) async {
    counts[adId] = (counts[adId] ?? 0) + 1;
  }
}

// 广告管理类，负责广告调度与显示
class AdManager with ChangeNotifier {
  // 文字广告配置常量
  static const double TEXT_AD_FONT_SIZE = 14.0; // 文字广告字体大小
  static const int TEXT_AD_REPETITIONS = 2; // 文字广告循环次数
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
  static const double TITLE_HEIGHT = 40.0; // 标题栏高度
  static const double MIN_IMAGE_WIDTH = 200.0; // 图片最小宽度
  static const double MIN_IMAGE_HEIGHT = 150.0; // 图片最小高度

  AdData? _adData; // 存储广告数据
  Map<String, int> _adShownCounts = {}; // 记录广告展示次数
  
  // 广告触发标志
  bool _hasTriggeredTextAdOnCurrentChannel = false; // 当前频道是否触发文字广告
  bool _hasTriggeredImageAdOnCurrentChannel = false; // 当前频道是否触发图片广告
  bool _hasTriggeredVideoAdOnCurrentChannel = false; // 当前频道是否触发视频广告
  
  // 广告显示状态
  bool _isShowingTextAd = false; // 是否显示文字广告
  bool _isShowingImageAd = false; // 是否显示图片广告
  bool _isShowingVideoAd = false; // 是否显示视频广告
  
  // 当前广告
  AdItem? _currentTextAd; // 当前文字广告
  AdItem? _currentImageAd; // 当前图片广告
  AdItem? _currentVideoAd; // 当前视频广告
  Size? _currentImageAdSize; // 当前图片广告尺寸
  
  String? _lastChannelId; // 上次频道ID
  
  // 定时器管理
  final Map<String, Timer> _textAdTimers = {}; // 文字广告定时器
  final Map<String, Timer> _imageAdTimers = {}; // 图片广告定时器
  
  // 调度时间追踪
  final Map<String, DateTime> _lastAdScheduleTimes = {}; // 广告最后调度时间
  
  BetterPlayerController? _adController; // 视频广告播放控制器
  
  // 图片广告倒计时
  int _imageAdRemainingSeconds = 0; // 图片广告剩余时间
  final ValueNotifier<int> imageAdCountdownNotifier = ValueNotifier<int>(0); // 倒计时通知器

  // 加载状态
  bool _isLoadingAdData = false; // 是否正在加载广告数据
  Completer<bool>? _adDataLoadedCompleter; // 广告数据加载完成器

  // 屏幕信息
  double _screenWidth = 0; // 屏幕宽度
  double _screenHeight = 0; // 屏幕高度
  bool _isLandscape = false; // 是否横屏
  TickerProvider? _vsyncProvider; // 动画同步提供者
  
  // 播放状态标志
  Map<String, bool> _adScheduledChannels = {}; // 记录已调度广告的频道
  Set<String> _advertisedChannels = {}; // 记录当前会话中已投放广告的频道

  AdManager() {
    _init(); // 构造时初始化
  }

  // 初始化广告管理器
  Future<void> _init() async {
    _adShownCounts = {}; // 初始化展示次数为空
    _adScheduledChannels = {}; // 初始化调度频道为空
    _advertisedChannels = {}; // 初始化已投放频道为空
    await loadAdData(); // 加载广告数据
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
      LogUtil.i('更新广告管理器屏幕信息: 宽=$width, 高=$height, 横屏=$isLandscape');
      if (_isShowingTextAd || _isShowingImageAd) notifyListeners(); // 有广告显示时更新UI
    }
  }
  
  // 处理频道切换逻辑
  void onChannelChanged(String channelId) {
    if (_lastChannelId == channelId) {
      LogUtil.i('频道ID未变化，跳过: $channelId');
      return;
    }
    LogUtil.i('检测到频道切换: $channelId');
    _lastChannelId = channelId;
    _cancelAllAdTimers(); // 取消所有定时器
    _hasTriggeredTextAdOnCurrentChannel = false;
    _hasTriggeredImageAdOnCurrentChannel = false;
    _hasTriggeredVideoAdOnCurrentChannel = false;
    if (_isShowingTextAd || _isShowingImageAd) _stopAllDisplayingAds(); // 停止显示的广告
    _adScheduledChannels[channelId] = false; // 重置频道调度状态
    LogUtil.i('频道已切换到: $channelId，等待视频播放后调度广告');
  }
  
  // 通知视频开始播放并调度广告
  void onVideoStartPlaying() {
    if (_lastChannelId == null) return;
    if (_adScheduledChannels[_lastChannelId] == true) {
      LogUtil.i('频道 $_lastChannelId 已经调度过广告，不重复触发');
      return;
    }
    _adScheduledChannels[_lastChannelId] = true; // 标记频道已调度
    if (_advertisedChannels.contains(_lastChannelId)) {
      LogUtil.i('频道 $_lastChannelId 在当前会话中已投放广告，不重复投放');
      return;
    }
    LogUtil.i('视频开始播放，现在开始调度广告');
    if (Config.adOn && _adData != null) {
      Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
        if (_lastChannelId != null) {
          _advertisedChannels.add(_lastChannelId!); // 添加到已投放频道
          _scheduleAdsForNewChannel(); // 调度新频道广告
        }
      });
    }
  }
  
  // 取消所有广告定时器
  void _cancelAllAdTimers() {
    void cancelTimersInMap(Map<String, Timer> timers) {
      timers.values.forEach((timer) => timer.isActive ? timer.cancel() : null);
      timers.clear();
    }
    cancelTimersInMap(_textAdTimers); // 取消文字广告定时器
    cancelTimersInMap(_imageAdTimers); // 取消图片广告定时器
  }
  
  // 停止所有正在显示的广告
  void _stopAllDisplayingAds() {
    bool needsNotify = false;
    if (_isShowingTextAd) {
      _isShowingTextAd = false;
      _currentTextAd = null;
      needsNotify = true;
    }
    if (_isShowingImageAd) {
      _isShowingImageAd = false;
      _currentImageAd = null;
      _currentImageAdSize = null;
      _imageAdRemainingSeconds = 0;
      imageAdCountdownNotifier.value = 0;
      needsNotify = true;
    }
    if (needsNotify) notifyListeners(); // 通知UI更新
  }
  
  // 为新频道安排广告，按优先级调度
  void _scheduleAdsForNewChannel() {
    if (_adData == null || _lastChannelId == null) return;
    AdItem? nextVideoAd = !_hasTriggeredVideoAdOnCurrentChannel ? _selectNextAd(_adData!.videoAds) : null;
    AdItem? nextImageAd = !_hasTriggeredImageAdOnCurrentChannel ? _selectNextAd(_adData!.imageAds) : null;
    AdItem? nextTextAd = !_hasTriggeredTextAdOnCurrentChannel ? _selectNextAd(_adData!.textAds) : null;
    LogUtil.i('为频道 $_lastChannelId 安排广告，可用广告: 视频=${nextVideoAd != null}, 图片=${nextImageAd != null}, 文字=${nextTextAd != null}');
    if (nextVideoAd != null) {
      LogUtil.i('检测到可用视频广告，等待外部触发播放');
    } else if (nextImageAd != null) {
      LogUtil.i('无视频广告，安排图片广告显示');
      _scheduleImageAd();
    } else if (nextTextAd != null) {
      LogUtil.i('只有文字广告可用，直接安排显示');
      _scheduleTextAd();
    } else {
      LogUtil.i('没有任何可用广告');
    }
  }
  
  // 检查是否正在调度文字广告
  bool _isSchedulingTextAd() => _textAdTimers.values.any((timer) => timer.isActive);

  // 调度文字广告
  void _scheduleTextAd() => _scheduleAdByType('text');

  // 调度图片广告
  void _scheduleImageAd() => _scheduleAdByType('image');
  
  // 按类型调度广告
  void _scheduleAdByType(String adType) {
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不安排${_getAdTypeName(adType)}');
      return;
    }
    final params = _getAdTypeParams(adType);
    if (params == null) return;
    final List<AdItem> adsList = params.adsList;
    final String logPrefix = params.logPrefix;
    final bool hasTriggered = params.hasTriggered;
    final int defaultDelay = params.defaultDelay;
    if (hasTriggered) {
      LogUtil.i('当前频道已触发$logPrefix，不重复安排');
      return;
    }
    bool otherAdShowing = _isShowingVideoAd || (adType == 'text' && _isShowingImageAd) || 
                         (adType == 'image' && _isShowingTextAd);
    if (otherAdShowing) {
      LogUtil.i('已有其他广告显示中，不安排$logPrefix，等待其结束');
      return;
    }
    if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('当前频道已播放视频广告，不显示图片广告');
      return;
    }
    final now = DateTime.now();
    if (_lastAdScheduleTimes.containsKey(adType) && 
        now.difference(_lastAdScheduleTimes[adType]!).inMilliseconds < MIN_RESCHEDULE_INTERVAL_MS) {
      LogUtil.i('$logPrefix调度过于频繁，间隔不足 $MIN_RESCHEDULE_INTERVAL_MS ms');
      return;
    }
    final nextAd = _selectNextAd(adsList);
    if (nextAd == null) {
      LogUtil.i('没有可显示的$logPrefix');
      _tryScheduleAlternativeAd(adType);
      return;
    }
    _lastAdScheduleTimes[adType] = now; // 记录调度时间
    final delaySeconds = nextAd.displayDelaySeconds ?? defaultDelay;
    LogUtil.i('安排$logPrefix ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    final timerId = '${adType}_${nextAd.id}_${now.millisecondsSinceEpoch}';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    if (adType == 'image') {
      LogUtil.i('开始预加载图片广告: ${nextAd.url}');
      _preloadImageAd(nextAd).then((imageSizeOpt) {
        if (imageSizeOpt != null) {
          _scheduleAdTimer(adType, nextAd, timerId, timersMap, delaySeconds, imageSizeOpt);
        } else {
          LogUtil.i('图片加载失败，尝试显示文字广告');
          _tryScheduleAlternativeAd('image');
        }
      });
    } else {
      _scheduleAdTimer(adType, nextAd, timerId, timersMap, delaySeconds, null);
    }
  }

  // 获取广告类型参数
  _AdTypeParams? _getAdTypeParams(String adType) {
    switch (adType) {
      case 'text':
        if (_adData == null) return null;
        return _AdTypeParams(adsList: _adData!.textAds, logPrefix: '文字广告', 
                            hasTriggered: _hasTriggeredTextAdOnCurrentChannel, defaultDelay: DEFAULT_TEXT_AD_DELAY);
      case 'image':
        if (_adData == null) return null;
        return _AdTypeParams(adsList: _adData!.imageAds, logPrefix: '图片广告', 
                            hasTriggered: _hasTriggeredImageAdOnCurrentChannel, defaultDelay: DEFAULT_IMAGE_AD_DELAY);
      default:
        LogUtil.e('未知广告类型: $adType');
        return null;
    }
  }
  
  // 获取广告类型名称
  String _getAdTypeName(String adType) {
    switch (adType) {
      case 'text': return '文字广告';
      case 'image': return '图片广告';
      case 'video': return '视频广告';
      default: return '未知广告';
    }
  }

  // 尝试调度替代广告
  void _tryScheduleAlternativeAd(String failedAdType) {
    if (failedAdType == 'text' && !_hasTriggeredImageAdOnCurrentChannel && 
        !_isShowingImageAd && !_hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('没有可用的文字广告，尝试调度图片广告');
      _scheduleAdByType('image');
    } else if (failedAdType == 'image' && !_hasTriggeredTextAdOnCurrentChannel && !_isShowingTextAd) {
      LogUtil.i('没有可用的图片广告，尝试调度文字广告');
      _scheduleAdByType('text');
    } else {
      LogUtil.i('无可用的替代广告，当前频道将不显示广告');
    }
  }

  // 安排广告定时器
  void _scheduleAdTimer(String adType, AdItem nextAd, String timerId, 
                       Map<String, Timer> timersMap, int delaySeconds, [Size? imageSize]) {
    timersMap[timerId] = Timer(Duration(seconds: delaySeconds), () {
      if (!Config.adOn || _isAdTypeTriggered(adType)) {
        LogUtil.i('延迟显示${_getAdTypeName(adType)}时条件已变化，取消显示');
        timersMap.remove(timerId);
        return;
      }
      if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
        LogUtil.i('延迟期间检测到视频广告已播放，取消图片广告');
        timersMap.remove(timerId);
        return;
      }
      if (_isShowingVideoAd || _isShowingImageAd || _isShowingTextAd) {
        LogUtil.i('其他广告正在显示，等待其结束再显示${_getAdTypeName(adType)}');
        _createAdWaitingTimer(adType, nextAd, timerId, imageSize);
        return;
      }
      _showAdByType(adType, nextAd, imageSize); // 显示广告
      timersMap.remove(timerId);
    });
  }
  
  // 检查广告类型是否已触发
  bool _isAdTypeTriggered(String adType) {
    switch (adType) {
      case 'text': return _hasTriggeredTextAdOnCurrentChannel;
      case 'image': return _hasTriggeredImageAdOnCurrentChannel;
      case 'video': return _hasTriggeredVideoAdOnCurrentChannel;
      default: return false;
    }
  }
  
  // 根据类型显示广告
  void _showAdByType(String adType, AdItem ad, [Size? imageSize]) {
    switch (adType) {
      case 'text': _showTextAd(ad); break;
      case 'image':
        if (imageSize != null) _showImageAd(ad, imageSize);
        else LogUtil.e('无法显示图片广告：尺寸信息丢失');
        break;
    }
  }
  
  // 创建广告等待定时器
  void _createAdWaitingTimer(String adType, AdItem ad, String timerId, [Size? imageSize]) {
    final waitTimerId = 'wait_$timerId';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    timersMap[waitTimerId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingImageAd && !_isShowingTextAd && !_isShowingVideoAd) {
        timer.cancel();
        timersMap.remove(waitTimerId);
        if (!Config.adOn || _isAdTypeTriggered(adType)) {
          LogUtil.i('等待期间条件已变化，取消显示${_getAdTypeName(adType)}');
          return;
        }
        if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
          LogUtil.i('等待期间检测到视频广告已播放，取消图片广告');
          return;
        }
        _showAdByType(adType, ad, imageSize); // 显示广告
      }
    });
  }
  
  // 显示文字广告
  void _showTextAd(AdItem ad) {
    _currentTextAd = ad;
    _isShowingTextAd = true;
    _incrementAdShownCount(ad.id); // 更新计数
    _hasTriggeredTextAdOnCurrentChannel = true;
    LogUtil.i('显示文字广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners(); // 通知UI更新
  }

  // 更新广告显示计数
  void _incrementAdShownCount(String adId) {
    _adShownCounts[adId] = (_adShownCounts[adId] ?? 0) + 1;
    AdCountManager.incrementAdCount(adId, _adShownCounts);
  }

  // 显示图片广告
  void _showImageAd(AdItem ad, Size preloadedSize) {
    _currentImageAd = ad;
    _currentImageAdSize = preloadedSize;
    _isShowingImageAd = true;
    _incrementAdShownCount(ad.id); // 更新计数
    _hasTriggeredImageAdOnCurrentChannel = true;
    _imageAdRemainingSeconds = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
    LogUtil.i('显示图片广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners(); // 通知UI更新
    _startImageAdCountdown(ad); // 启动倒计时
  }

  // 图片广告倒计时并安排后续文字广告
  void _startImageAdCountdown(AdItem ad) {
    final duration = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    _imageAdRemainingSeconds = duration;
    imageAdCountdownNotifier.value = duration;
    final countdownTimerId = 'countdown_${ad.id}_${DateTime.now().millisecondsSinceEpoch}';
    _imageAdTimers[countdownTimerId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_imageAdRemainingSeconds <= 1) {
        timer.cancel();
        _imageAdTimers.remove(countdownTimerId);
        _isShowingImageAd = false;
        _currentImageAd = null;
        _currentImageAdSize = null;
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        notifyListeners();
        if (!_hasTriggeredTextAdOnCurrentChannel && _adData != null) {
          LogUtil.i('图片广告结束，安排文字广告');
          _scheduleTextAd();
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    });
  }

  // 随机选择下一个广告
  AdItem? _selectNextAd(List<AdItem> candidates) {
    if (candidates.isEmpty || !Config.adOn) return null;
    final validAds = candidates.where((ad) => 
      ad.enabled && (_adShownCounts[ad.id] ?? 0) < ad.displayCount).toList();
    if (validAds.isEmpty) return null;
    validAds.shuffle();
    return validAds.first; // 返回随机有效广告
  }

  // 构建带时间戳的API URL
  String _buildApiUrl(String baseUrl) => _addTimestampToUrl(baseUrl, _getCurrentTimestamp());

  // 获取当前时间戳
  String _getCurrentTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  // 加载广告数据
  Future<bool> loadAdData() async {
    if (_isLoadingAdData) return _adDataLoadedCompleter?.future ?? Future.value(false);
    _isLoadingAdData = true;
    _adDataLoadedCompleter = Completer<bool>();
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不加载广告数据');
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
    try {
      _adShownCounts = await AdCountManager.loadAdCounts(); // 加载计数
      final mainUrl = _buildApiUrl(Config.adApiUrl);
      LogUtil.i('加载广告数据，主API: $mainUrl');
      AdData? adData = await _loadAdDataFromUrl(mainUrl);
      if (adData == null && Config.backupAdApiUrl.isNotEmpty) {
        final backupUrl = _buildApiUrl(Config.backupAdApiUrl);
        LogUtil.i('主API加载失败，尝试备用API: $backupUrl');
        adData = await _loadAdDataFromUrl(backupUrl);
      }
      if (adData != null && !adData.isEmpty) {
        _adData = adData;
        LogUtil.i('广告数据加载成功: 文字=${adData.textAds.length}, 视频=${adData.videoAds.length}, 图片=${adData.imageAds.length}');
        if (_lastChannelId != null && _adScheduledChannels[_lastChannelId] == true && 
            !_advertisedChannels.contains(_lastChannelId!)) {
          _scheduleAdsForNewChannel(); // 安排广告
          _advertisedChannels.add(_lastChannelId!);
        }
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(true);
        return true;
      } else {
        _adData = null;
        LogUtil.e('广告数据加载失败: 数据为空或格式不正确');
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      LogUtil.e('加载广告数据发生异常: $e');
      _adData = null;
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
  }

  // 从指定URL加载广告数据
  Future<AdData?> _loadAdDataFromUrl(String url) async {
    try {
      final response = await HttpUtil().getRequest(url, parseData: (data) {
        if (data is! Map<String, dynamic>) {
          LogUtil.e('广告数据格式不正确，期望JSON对象，实际为: $data');
          return null;
        }
        if (data.containsKey('text_ads') || data.containsKey('video_ads') || data.containsKey('image_ads')) {
          return AdData.fromJson(data);
        } else {
          LogUtil.e('广告数据格式不符合预期');
          return null;
        }
      });
      return response; // 返回解析后的广告数据
    } catch (e) {
      LogUtil.e('从URL加载广告数据失败: $e');
      return null;
    }
  }

  // 为URL添加时间戳参数
  String _addTimestampToUrl(String originalUrl, String timestamp) {
    try {
      final uri = Uri.parse(originalUrl);
      final queryParams = Map<String, String>.from(uri.queryParameters)..['t'] = timestamp;
      return Uri(scheme: uri.scheme, host: uri.host, path: uri.path, queryParameters: queryParams, port: uri.port).toString();
    } catch (e) {
      LogUtil.e('添加时间戳到URL失败: $e，返回原始URL');
      return originalUrl.contains('?') ? '$originalUrl&t=$timestamp' : '$originalUrl?t=$timestamp';
    }
  }

  // 异步检查是否需要播放视频广告
  Future<bool> shouldPlayVideoAdAsync() async {
    if (_adData == null && !_isLoadingAdData) await loadAdData();
    else if (_adData == null && _isLoadingAdData && _adDataLoadedCompleter != null) await _adDataLoadedCompleter!.future;
    return shouldPlayVideoAd(); // 返回检查结果
  }

  // 判断是否需要播放视频广告
  bool shouldPlayVideoAd() {
    if (!Config.adOn || _adData == null || _lastChannelId == null) return false;
    if (_advertisedChannels.contains(_lastChannelId!)) return false;
    if (_hasTriggeredVideoAdOnCurrentChannel) return false;
    if (_isShowingTextAd || _isShowingImageAd || _isShowingVideoAd) return false;
    final nextAd = _selectNextAd(_adData!.videoAds);
    if (nextAd == null) return false;
    _currentVideoAd = nextAd;
    LogUtil.i('需要播放视频广告: ${nextAd.id}');
    return true;
  }

  // 播放视频广告
  Future<void> playVideoAd() async {
    if (!Config.adOn || _currentVideoAd == null || _lastChannelId == null) return;
    _advertisedChannels.add(_lastChannelId!); // 添加到已投放频道
    final videoAd = _currentVideoAd!;
    LogUtil.i('开始播放视频广告: ${videoAd.url}');
    _isShowingVideoAd = true;
    _hasTriggeredVideoAdOnCurrentChannel = true;
    notifyListeners();
    final adCompletion = Completer<void>();
    try {
      final adDataSource = BetterPlayerConfig.createDataSource(url: videoAd.url!, isHls: _isHlsStream(videoAd.url));
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: _isHlsStream(videoAd.url),
        eventListener: (event) => _videoAdEventListener(event, adCompletion),
      );
      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();
      await adCompletion.future.timeout(Duration(seconds: VIDEO_AD_TIMEOUT_SECONDS), onTimeout: () {
        LogUtil.i('广告播放超时，默认结束');
        _cleanupAdController();
        if (!adCompletion.isCompleted) adCompletion.complete();
      });
    } catch (e) {
      LogUtil.e('视频广告播放失败: $e');
      _cleanupAdController();
      if (!adCompletion.isCompleted) adCompletion.completeError(e);
    } finally {
      _incrementAdShownCount(videoAd.id); // 更新计数
      _isShowingVideoAd = false;
      _currentVideoAd = null;
      LogUtil.i('广告播放结束，次数: ${_adShownCounts[videoAd.id]} / ${videoAd.displayCount}');
      notifyListeners();
      _hasTriggeredTextAdOnCurrentChannel = true; // 防止后续文字广告
      _hasTriggeredImageAdOnCurrentChannel = true; // 防止后续图片广告
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
    _adController?.dispose();
    _adController = null;
  }

  // 重置广告状态
  void reset({bool rescheduleAds = true, bool preserveTimers = false}) {
    final currentChannelId = _lastChannelId;
    _cleanupAdController();
    _isShowingVideoAd = false;
    _currentVideoAd = null;
    if (!preserveTimers) _cancelAllAdTimers();
    if (_isShowingTextAd) {
      _isShowingTextAd = false;
      _currentTextAd = null;
    }
    if (_isShowingImageAd) {
      _isShowingImageAd = false;
      _currentImageAd = null;
      _currentImageAdSize = null;
      _imageAdRemainingSeconds = 0;
      imageAdCountdownNotifier.value = 0;
    }
    LogUtil.i('广告管理器状态已重置，重新安排广告: $rescheduleAds, 保留计时器: $preserveTimers');
    notifyListeners();
  }

  // 释放所有资源
  @override
  void dispose() {
    _cleanupAdController();
    _cancelAllAdTimers();
    _isShowingTextAd = false;
    _isShowingImageAd = false;
    _isShowingVideoAd = false;
    _currentTextAd = null;
    _currentImageAd = null;
    _currentVideoAd = null;
    _currentImageAdSize = null;
    _adData = null;
    _vsyncProvider = null;
    _adScheduledChannels.clear();
    _advertisedChannels.clear();
    LogUtil.i('广告管理器资源已释放');
    super.dispose();
  }

  // 检查是否显示文字广告
  bool getShowTextAd() {
    final show = _isShowingTextAd && _currentTextAd != null && _currentTextAd!.content != null && Config.adOn;
    if (_isShowingTextAd && !show) LogUtil.i('文字广告条件检查失败');
    return show;
  }

  // 检查是否显示图片广告
  bool getShowImageAd() => _isShowingImageAd && _currentImageAd != null && Config.adOn;

  // 获取文字广告内容
  String? getTextAdContent() => _currentTextAd?.content;

  // 获取文字广告链接
  String? getTextAdLink() => _currentTextAd?.link;

  // 获取当前图片广告
  AdItem? getCurrentImageAd() => _isShowingImageAd ? _currentImageAd : null;

  // 获取视频广告控制器
  BetterPlayerController? getAdController() => _adController;

  // 构建文字广告Widget
  Widget buildTextAdWidget() {
    if (!getShowTextAd() || _currentTextAd?.content == null) return const SizedBox.shrink();
    final content = getTextAdContent()!;
    return Positioned(
      top: TEXT_AD_TOP_POSITION,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => _currentTextAd?.link?.isNotEmpty ?? false ? handleAdClick(_currentTextAd!.link) : null,
        child: Container(
          width: double.infinity,
          height: TEXT_AD_FONT_SIZE * 1.5,
          color: Colors.black.withOpacity(0.5),
          child: Marquee(
            text: content,
            style: const TextStyle(color: Colors.white, fontSize: TEXT_AD_FONT_SIZE, shadows: [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.5, color: Colors.black)]),
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
              LogUtil.i('文字广告完成所有循环');
              _isShowingTextAd = false;
              _currentTextAd = null;
              WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
            },
          ),
        ),
      ),
    );
  }

  // 构建图片广告Widget
  Widget buildImageAdWidget() {
    if (!getShowImageAd() || _currentImageAd == null || _currentImageAdSize == null) return const SizedBox.shrink();
    final imageAd = _currentImageAd!;
    final imageSize = _currentImageAdSize!;
    final aspectRatio = imageSize.width / imageSize.height;
    double imageWidth = aspectRatio > 1 ? min(_screenWidth * 0.8, imageSize.width) : (min(_screenHeight * 0.7, imageSize.height) * aspectRatio);
    double imageHeight = aspectRatio > 1 ? imageWidth / aspectRatio : min(_screenHeight * 0.7, imageSize.height);
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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), spreadRadius: 3, blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: TITLE_HEIGHT,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                decoration: BoxDecoration(color: Colors.blue.shade800, borderRadius: BorderRadius.only(topLeft: Radius.circular(BORDER_RADIUS), topRight: Radius.circular(BORDER_RADIUS))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('推广内容', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        const Text('广告关闭倒计时: ', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ValueListenableBuilder<int>(
                          valueListenable: imageAdCountdownNotifier,
                          builder: (context, remainingSeconds, child) => Text('$remainingSeconds秒', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
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
                  onTap: () => imageAd.link?.isNotEmpty ?? false ? handleAdClick(imageAd.link) : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(BORDER_RADIUS), bottomRight: Radius.circular(BORDER_RADIUS)),
                    child: Image.network(
                      imageAd.url!,
                      fit: BoxFit.fill,
                      width: imageWidth,
                      height: imageHeight,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[900], child: Center(child: Text('广告加载失败', style: TextStyle(color: Colors.white70, fontSize: 16)))),
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
    try {
      LogUtil.i('开始预加载图片: ${ad.url}');
      final Completer<Size?> completer = Completer();
      final imageProvider = NetworkImage(ad.url!);
      final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
      ImageStreamListener? listener;
      Timer? timeoutTimer;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
          LogUtil.i('图片预加载成功，尺寸: ${size.width}x${size.height}');
          completer.complete(size);
          if (timeoutTimer?.isActive ?? false) timeoutTimer!.cancel();
          stream.removeListener(listener!);
        },
        onError: (exception, stackTrace) {
          LogUtil.e('加载图片失败: $exception');
          completer.complete(null);
          if (timeoutTimer?.isActive ?? false) timeoutTimer!.cancel();
          stream.removeListener(listener!);
        },
      );
      stream.addListener(listener);
      timeoutTimer = Timer(Duration(seconds: IMAGE_PRELOAD_TIMEOUT_SECONDS), () {
        if (!completer.isCompleted) {
          LogUtil.i('获取图片尺寸超时，放弃加载');
          completer.complete(null);
          stream.removeListener(listener!);
        }
      });
      return await completer.future;
    } catch (e) {
      LogUtil.e('预加载图片过程中发生异常: $e');
      return null;
    }
  }

  // 处理广告点击跳转
  Future<void> handleAdClick(String? link) async {
    if (link == null || link.isEmpty) return;
    try {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        LogUtil.i('已打开广告链接: $link');
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
