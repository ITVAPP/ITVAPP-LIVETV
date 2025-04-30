import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/config.dart';

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

// 单个广告项模型
class AdItem {
  final String id;
  final String? content;     // 文字广告内容
  final String? url;         // 视频/图片广告URL
  final bool enabled;
  final int displayCount;
  final int? displayDelaySeconds;
  final int? durationSeconds; // 图片广告显示时长
  final String? link;        // 可选的点击链接
  final String type;         // 'text', 'video', 'image'

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
  final List<AdItem> textAds;
  final List<AdItem> videoAds;
  final List<AdItem> imageAds;

  const AdData({
    required this.textAds,
    required this.videoAds,
    required this.imageAds,
  });

  // 封装解析逻辑为可复用函数
  static List<AdItem> _parseAdItems(List? adsList, String type, {
    String? idPrefix,
    bool needsContent = false,
    bool needsUrl = false,
  }) {
    if (adsList == null || adsList.isEmpty) return [];
    
    return adsList.map((item) {
      // 检查必要字段
      if (needsContent && (item['content'] == null || item['content'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少必要的 content 字段，跳过此项');
        return null;
      }
      
      if (needsUrl && (item['url'] == null || item['url'].toString().isEmpty)) {
        LogUtil.i('$type 广告缺少必要的 url 字段，跳过此项');
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
    }).whereType<AdItem>().toList(); // 过滤掉null值
  }

  factory AdData.fromJson(Map<String, dynamic> json) {
    // 直接处理根级数据
    final data = json;
    
    return AdData(
      textAds: _parseAdItems(
        data['text_ads'] as List?,
        'text',
        idPrefix: 'text',
        needsContent: true,
      ),
      videoAds: _parseAdItems(
        data['video_ads'] as List?,
        'video',
        idPrefix: 'video',
        needsUrl: true,
      ),
      imageAds: _parseAdItems(
        data['image_ads'] as List?,
        'image',
        idPrefix: 'image',
        needsUrl: true,
      ),
    );
  }
  
  // 添加辅助方法检查是否为空
  bool get isEmpty => textAds.isEmpty && videoAds.isEmpty && imageAds.isEmpty;
}

// 广告计数管理辅助类 - 保留类定义但不使用持久化功能
class AdCountManager {
  // 加载广告已显示次数
  static Future<Map<String, int>> loadAdCounts() async {
    // 不再从持久化存储加载，直接返回空映射
    return {};
  }

  // 保存广告已显示次数
  static Future<void> saveAdCounts(Map<String, int> counts) async {
    // 不再保存到持久化存储，此方法为空实现
  }

  // 增加广告显示次数
  static Future<void> incrementAdCount(String adId, Map<String, int> counts) async {
    counts[adId] = (counts[adId] ?? 0) + 1;
    // 不再保存到持久化存储
  }
}

// 广告管理类
class AdManager with ChangeNotifier {
  // 文字广告相关常量
  static const double TEXT_AD_FONT_SIZE = 14.0; // 文字广告字体大小
  static const int TEXT_AD_REPETITIONS = 2; // 文字广告循环次数
  // [新增] 文字广告滚动速度常量 (像素/秒)
  static const double TEXT_AD_SCROLL_VELOCITY = 38.0;
  
  // 广告位置常量
  static const double TEXT_AD_TOP_POSITION_LANDSCAPE = 10.0; // 横屏模式下距顶部像素
  static const double TEXT_AD_TOP_POSITION_PORTRAIT = 15.0; // 竖屏模式下距顶部像素

  // 时间相关常量
  static const int MIN_RESCHEDULE_INTERVAL_MS = 2000; // 最小重新调度间隔
  static const int CHANNEL_CHANGE_DELAY_MS = 500;    // 频道切换后延迟调度
  static const int DEFAULT_IMAGE_AD_DURATION = 8;    // 默认图片广告持续时间
  static const int DEFAULT_TEXT_AD_DELAY = 10;       // 默认文字广告延迟时间
  static const int DEFAULT_IMAGE_AD_DELAY = 20;      // 默认图片广告延迟时间
  static const int VIDEO_AD_TIMEOUT_SECONDS = 36;    // 视频广告超时时间

  // 广告数据
  AdData? _adData; 
  Map<String, int> _adShownCounts = {}; // 各广告已显示次数
  
  // 广告触发标志
  bool _hasTriggeredTextAdOnCurrentChannel = false;
  bool _hasTriggeredImageAdOnCurrentChannel = false;
  bool _hasTriggeredVideoAdOnCurrentChannel = false;
  
  // 广告显示状态
  bool _isShowingTextAd = false;
  bool _isShowingImageAd = false;
  bool _isShowingVideoAd = false;
  
  // 当前显示的广告
  AdItem? _currentTextAd;
  AdItem? _currentImageAd;
  AdItem? _currentVideoAd;
  
  // 频道跟踪
  String? _lastChannelId;
  
  // 定时器集合
  final Map<String, Timer> _textAdTimers = {};
  final Map<String, Timer> _imageAdTimers = {};
  
  // 时间追踪，避免频繁调度
  final Map<String, DateTime> _lastAdScheduleTimes = {};
  
  // 媒体控制器
  BetterPlayerController? _adController;
  // [移除] 不再需要这些动画控制器
  // AnimationController? _textAdAnimationController;
  // Animation<double>? _textAdAnimation;
  
  // 图片广告倒计时
  int _imageAdRemainingSeconds = 0;
  final ValueNotifier<int> imageAdCountdownNotifier = ValueNotifier<int>(0);

  // 加载状态管理
  bool _isLoadingAdData = false;
  Completer<bool>? _adDataLoadedCompleter;

  // 屏幕信息
  double _screenWidth = 0;
  double _screenHeight = 0;
  bool _isLandscape = false;
  TickerProvider? _vsyncProvider;

  AdManager() {
    _init();
  }

  // 初始化
  Future<void> _init() async {
    _adShownCounts = {};
    await loadAdData();
  }

  // 更新屏幕信息
  void updateScreenInfo(double width, double height, bool isLandscape, TickerProvider vsync) {
    bool needsUpdate = _screenWidth != width || 
                     _screenHeight != height || 
                     _isLandscape != isLandscape ||
                     _vsyncProvider != vsync;
                     
    if (needsUpdate) {
      _screenWidth = width;
      _screenHeight = height;
      _isLandscape = isLandscape;
      _vsyncProvider = vsync;
      
      LogUtil.i('更新广告管理器屏幕信息: 宽=$width, 高=$height, 横屏=$isLandscape');
      
      // [修改] 使用Marquee后不再需要更新动画
      // 如果有文字广告正在显示，通知UI更新
      if (_isShowingTextAd && _currentTextAd != null) {
        notifyListeners();
      }
      
      notifyListeners();
    }
  }
  
  // 频道切换处理
  void onChannelChanged(String channelId) {
    // 避免重复通知
    if (_lastChannelId == channelId) {
      LogUtil.i('频道ID未变化，跳过: $channelId');
      return;
    }
    
    LogUtil.i('检测到频道切换: $channelId');
    _lastChannelId = channelId;
    
    // 取消所有正在等待的广告计时器
    _cancelAllAdTimers();
    
    // 重置触发标志
    _hasTriggeredTextAdOnCurrentChannel = false;
    _hasTriggeredImageAdOnCurrentChannel = false;
    _hasTriggeredVideoAdOnCurrentChannel = false;
    
    // 如果当前有任何广告在显示，先停止它们
    if (_isShowingTextAd || _isShowingImageAd) {
      _stopAllDisplayingAds();
    }
    
    // 有广告数据时，延迟一小段时间后安排广告
    if (_adData != null && Config.adOn) {
      Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
        // 再次确认频道未变化
        if (_lastChannelId == channelId) {
          _scheduleAdsForNewChannel();
        }
      });
    }
  }
  
  // 取消所有广告计时器
  void _cancelAllAdTimers() {
    // 使用 forEach 更简洁地取消所有定时器
    _textAdTimers.values.forEach((timer) => timer.cancel());
    _textAdTimers.clear();
    
    _imageAdTimers.values.forEach((timer) => timer.cancel());
    _imageAdTimers.clear();
  }
  
  // 停止所有正在显示的广告
  void _stopAllDisplayingAds() {
    if (_isShowingTextAd) {
      // [修改] 不再需要手动控制动画
      // _textAdAnimationController?.stop();
      // _textAdAnimationController?.reset();
      _isShowingTextAd = false;
      _currentTextAd = null;
    }
    
    if (_isShowingImageAd) {
      _isShowingImageAd = false;
      _currentImageAd = null;
      _imageAdRemainingSeconds = 0;
      imageAdCountdownNotifier.value = 0;
    }
    
    notifyListeners();
  }
  
  // [修改] 为新频道安排广告 - 改为按优先级顺序安排不同类型广告
  void _scheduleAdsForNewChannel() {
    if (_adData == null) return;
    
    // 检查各类型广告是否有可用
    AdItem? nextVideoAd = null;
    AdItem? nextImageAd = null;
    AdItem? nextTextAd = null;
    
    // 只预先检查是否有可用广告，并不安排显示
    if (!_hasTriggeredVideoAdOnCurrentChannel) {
      nextVideoAd = _selectNextAd(_adData!.videoAds);
    }
    
    if (!_hasTriggeredImageAdOnCurrentChannel) {
      nextImageAd = _selectNextAd(_adData!.imageAds);
    }
    
    if (!_hasTriggeredTextAdOnCurrentChannel) {
      nextTextAd = _selectNextAd(_adData!.textAds);
    }
    
    LogUtil.i('为新频道安排广告，可用广告: 视频=${nextVideoAd != null}, 图片=${nextImageAd != null}, 文字=${nextTextAd != null}');
    
    // 安排显示优先级: 视频 > 图片 > 文字
    if (nextVideoAd != null) {
      // 视频广告由外部机制触发，这里不做标记
      LogUtil.i('检测到可用视频广告，等待外部触发播放');
      // 视频广告结束后会安排文字广告
    } 
    else if (nextImageAd != null) {
      // 无视频广告，安排图片广告
      LogUtil.i('无视频广告，安排图片广告显示');
      _scheduleImageAd();
      // 图片广告结束后的回调中会安排文字广告
    }
    else if (nextTextAd != null) {
      // 只有文字广告可用
      LogUtil.i('只有文字广告可用，直接安排显示');
      _scheduleTextAd();
    }
    else {
      LogUtil.i('没有任何可用广告');
    }
  }
  
  // 检查是否有文字广告正在调度中
  bool _isSchedulingTextAd() {
    return _textAdTimers.values.any((timer) => timer.isActive);
  }
  
  // 改进的广告调度方法
  void _scheduleAdByType(String adType) {
    // 选择合适的广告列表和参数
    List<AdItem> adsList;
    String logPrefix;
    bool hasTriggered;
    bool otherAdShowing;
    int defaultDelay;
    Function(AdItem) showAdFunc;
    
    switch (adType) {
      case 'text':
        if (_adData == null) return;
        adsList = _adData!.textAds;
        logPrefix = '文字广告';
        hasTriggered = _hasTriggeredTextAdOnCurrentChannel;
        otherAdShowing = _isShowingVideoAd || _isShowingImageAd;
        defaultDelay = DEFAULT_TEXT_AD_DELAY;
        showAdFunc = _showTextAd;
        break;
      case 'image':
        if (_adData == null) return;
        adsList = _adData!.imageAds;
        logPrefix = '图片广告';
        hasTriggered = _hasTriggeredImageAdOnCurrentChannel;
        otherAdShowing = _isShowingVideoAd || _isShowingTextAd;
        defaultDelay = DEFAULT_IMAGE_AD_DELAY;
        showAdFunc = _showImageAd;
        break;
      default:
        LogUtil.e('未知广告类型: $adType');
        return;
    }
    
    // 检查基本条件
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不安排$logPrefix');
      return;
    }
    
    // 检查是否已经触发
    if (hasTriggered) {
      LogUtil.i('当前频道已触发$logPrefix，不重复安排');
      return;
    }
    
    // 检查是否正在显示其他广告
    if (otherAdShowing) {
      LogUtil.i('已有其他广告显示中，不安排$logPrefix，等待其结束');
      // 文字广告可以在其他广告结束后安排，不再此处增加等待逻辑
      // 而是在对应广告的结束回调中进行安排
      return;
    }
    
    // 特殊检查：如果是图片广告，且当前频道已播放过视频广告，则不显示图片广告
    if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('当前频道已播放过视频广告，不再显示图片广告');
      return;
    }
    
    // 检查调度时间间隔
    final now = DateTime.now();
    if (_lastAdScheduleTimes.containsKey(adType)) {
      final timeSinceLastSchedule = now.difference(_lastAdScheduleTimes[adType]!).inMilliseconds;
      if (timeSinceLastSchedule < MIN_RESCHEDULE_INTERVAL_MS) {
        LogUtil.i('$logPrefix调度过于频繁，间隔仅 $timeSinceLastSchedule ms，最小需要 $MIN_RESCHEDULE_INTERVAL_MS ms');
        return;
      }
    }
    
    // [修改] 选择下一个要显示的广告 - 使用随机选择而非按展示次数排序
    final nextAd = _selectNextAd(adsList);
    if (nextAd == null) {
      LogUtil.i('没有可显示的$logPrefix');
      
      // 如果是文字广告且无可用，尝试安排图片广告作为替代 (除非已显示过视频广告)
      if (adType == 'text' && !_hasTriggeredImageAdOnCurrentChannel && 
          !_isShowingImageAd && !_hasTriggeredVideoAdOnCurrentChannel) {
        _scheduleImageAd();
      }
      return;
    }
    
    // 记录最后调度时间
    _lastAdScheduleTimes[adType] = now;
    
    // 使用广告指定的延迟时间
    final delaySeconds = nextAd.displayDelaySeconds ?? defaultDelay;
    LogUtil.i('安排$logPrefix ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    // 创建定时器
    final timerId = '${adType}_${nextAd.id}_${now.millisecondsSinceEpoch}';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    
    timersMap[timerId] = Timer(Duration(seconds: delaySeconds), () {
      // 延迟期满后再次检查条件
      if (!Config.adOn || (adType == 'text' && _hasTriggeredTextAdOnCurrentChannel) || 
          (adType == 'image' && _hasTriggeredImageAdOnCurrentChannel)) {
        LogUtil.i('延迟显示$logPrefix时条件已变化，取消显示');
        timersMap.remove(timerId);
        return;
      }
      
      // 再次检查：如果是图片广告，且当前频道已播放过视频广告，则不显示
      if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
        LogUtil.i('延迟期间检测到当前频道已播放过视频广告，取消显示图片广告');
        timersMap.remove(timerId);
        return;
      }
      
      // 如果有其他广告在显示，等待其结束
      if ((_isShowingVideoAd || _isShowingImageAd || _isShowingTextAd)) {
        LogUtil.i('其他广告正在显示，等待其结束再显示$logPrefix');
        // 创建一个检查器定时器，定期检查其他广告是否结束
        _createAdWaitingTimer(adType, nextAd, timerId);
        return;
      }
      
      // 开始显示广告
      showAdFunc(nextAd);
      timersMap.remove(timerId);
    });
  }
  
  // 统一的广告等待定时器创建
  void _createAdWaitingTimer(String adType, AdItem ad, String timerId) {
    final waitTimerId = 'wait_$timerId';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    
    timersMap[waitTimerId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingImageAd && !_isShowingTextAd && !_isShowingVideoAd) {
        timer.cancel();
        timersMap.remove(waitTimerId);
        
        // 再次检查条件
        if (!Config.adOn || (adType == 'text' && _hasTriggeredTextAdOnCurrentChannel) || 
            (adType == 'image' && _hasTriggeredImageAdOnCurrentChannel)) {
          LogUtil.i('等待期间条件已变化，取消显示${adType == 'text' ? '文字广告' : '图片广告'}');
          return;
        }
        
        // 特殊检查：如果是图片广告，且当前频道已播放过视频广告，则不显示
        if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
          LogUtil.i('等待期间检测到当前频道已播放过视频广告，取消显示图片广告');
          return;
        }
        
        if (adType == 'text') {
          _showTextAd(ad);
        } else {
          _showImageAd(ad);
        }
      }
    });
  }
  
  // 简化后的广告调度接口方法
  void _scheduleTextAd() {
    _scheduleAdByType('text');
  }
  
  void _scheduleImageAd() {
    _scheduleAdByType('image');
  }
  
  // 显示文字广告
  void _showTextAd(AdItem ad) {
    _currentTextAd = ad;
    _isShowingTextAd = true;
    _adShownCounts[ad.id] = (_adShownCounts[ad.id] ?? 0) + 1;
    _hasTriggeredTextAdOnCurrentChannel = true;
    
    LogUtil.i('显示文字广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    
    // [修改] 使用Marquee后不再需要初始化动画
    // _updateTextAdAnimation();
    
    notifyListeners();
  }

  // 显示图片广告
  void _showImageAd(AdItem ad) {
    _currentImageAd = ad;
    _isShowingImageAd = true;
    _adShownCounts[ad.id] = (_adShownCounts[ad.id] ?? 0) + 1;
    _hasTriggeredImageAdOnCurrentChannel = true;
    
    // 设置初始倒计时
    _imageAdRemainingSeconds = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
    
    LogUtil.i('显示图片广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners();
    
    // 设置自动关闭和倒计时
    _startImageAdCountdown(ad);
  }
  
  // [修改] 图片广告倒计时 - 在结束后安排文字广告
  void _startImageAdCountdown(AdItem ad) {
    final duration = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    _imageAdRemainingSeconds = duration;
    imageAdCountdownNotifier.value = duration;
    
    // 使用命名定时器，以便在需要时取消
    final countdownTimerId = 'countdown_${ad.id}_${DateTime.now().millisecondsSinceEpoch}';
    _imageAdTimers[countdownTimerId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_imageAdRemainingSeconds <= 1) {
        timer.cancel();
        _imageAdTimers.remove(countdownTimerId);
        _isShowingImageAd = false;
        _currentImageAd = null;
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        notifyListeners();
        
        // 图片广告结束后，检查是否可以显示文字广告
        if (!_hasTriggeredTextAdOnCurrentChannel && _adData != null) {
          LogUtil.i('图片广告结束，安排文字广告');
          _scheduleTextAd();
        } else {
          LogUtil.i('图片广告结束，但文字广告已触发，不再安排其他广告');
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    });
  }
  
  // [修改] 简化文字广告动画更新方法，因为现在使用Marquee包
  void _updateTextAdAnimation() {
    LogUtil.i('文字广告动画已启动，类似MARQUEE效果，将循环 $TEXT_AD_REPETITIONS 次');
    // 不再需要初始化动画控制器，只需通知UI更新
    notifyListeners();
  }

  // [修改] 选择下一个显示的广告 - 改为随机选择
  AdItem? _selectNextAd(List<AdItem> candidates) {
    if (candidates.isEmpty) return null;
    
    // 检查全局广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已全局关闭');
      return null;
    }
    
    // 筛选有效的广告项
    final validAds = candidates.where((ad) => 
      ad.enabled && 
      (_adShownCounts[ad.id] ?? 0) < ad.displayCount
    ).toList();
    
    if (validAds.isEmpty) return null;
    
    // [修改] 随机选择一条广告，而非按显示次数排序
    validAds.shuffle(); // 随机打乱顺序
    return validAds.first;
  }
  
  // 统一处理API URL构建
  String _buildApiUrl(String baseUrl) {
    // 生成时间戳，格式为：yyyyMMddHHmmss
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    
    // 添加时间戳参数到URL
    return _addTimestampToUrl(baseUrl, timestamp);
  }

  // 改进的广告加载方法
  Future<bool> loadAdData() async {
    // 避免重复加载
    if (_isLoadingAdData) {
      // 如果正在加载，等待加载完成
      if (_adDataLoadedCompleter != null) {
        return _adDataLoadedCompleter!.future;
      }
    }
    
    _isLoadingAdData = true;
    _adDataLoadedCompleter = Completer<bool>();
    
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不加载广告数据');
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
    
    try {
      // 先尝试主API
      final mainUrl = _buildApiUrl(Config.adApiUrl);
      LogUtil.i('加载广告数据，主API: $mainUrl');
      
      // 尝试加载广告数据
      AdData? adData = await _loadAdDataFromUrl(mainUrl);
      
      // 如果主API失败且有备用API，尝试备用API
      if (adData == null && Config.backupAdApiUrl.isNotEmpty) {
        final backupUrl = _buildApiUrl(Config.backupAdApiUrl);
        LogUtil.i('主API加载失败，尝试备用API: $backupUrl');
        adData = await _loadAdDataFromUrl(backupUrl);
      }
      
      // 处理结果
      if (adData != null && !adData.isEmpty) {
        _adData = adData;
        LogUtil.i('广告数据加载成功: 文字广告: ${adData.textAds.length}个, 视频广告: ${adData.videoAds.length}个, 图片广告: ${adData.imageAds.length}个');
        
        // 为每种类型安排广告显示
        if (_lastChannelId != null) {
          _scheduleAdsForNewChannel();
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

  // 从特定URL加载广告数据
  Future<AdData?> _loadAdDataFromUrl(String url) async {
    try {
      final response = await HttpUtil().getRequest(
        url,
        parseData: (data) {
          if (data is! Map<String, dynamic>) {
            LogUtil.e('广告数据格式不正确，期望 JSON 对象，实际为: $data');
            return null;
          }
          
          // 只处理新格式的广告数据
          if (data.containsKey('text_ads') || data.containsKey('video_ads') || 
              data.containsKey('image_ads')) {
            return AdData.fromJson(data);
          } else {
            LogUtil.e('广告数据格式不符合预期');
            return null;
          }
        },
      );
      
      return response;
    } catch (e) {
      LogUtil.e('从URL加载广告数据失败: $e');
      return null;
    }
  }

  // 向URL添加时间戳的辅助方法
  String _addTimestampToUrl(String originalUrl, String timestamp) {
    try {
      final uri = Uri.parse(originalUrl);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      
      // 添加时间戳参数
      queryParams['t'] = timestamp;
      
      // 重建URL
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        path: uri.path,
        queryParameters: queryParams,
        port: uri.port,  // 保留原始端口
      ).toString();
    } catch (e) {
      LogUtil.e('添加时间戳到URL失败: $e，返回原始URL');
      // 出错时简单地在URL后附加时间戳
      if (originalUrl.contains('?')) {
        return '$originalUrl&t=$timestamp';
      } else {
        return '$originalUrl?t=$timestamp';
      }
    }
  }

  // 异步版本的视频广告检查
  Future<bool> shouldPlayVideoAdAsync() async {
    // 确保广告数据已加载
    if (_adData == null && !_isLoadingAdData) {
      await loadAdData();
    } else if (_adData == null && _isLoadingAdData && _adDataLoadedCompleter != null) {
      await _adDataLoadedCompleter!.future;
    }
    
    return shouldPlayVideoAd();
  }

  // 判断是否需要播放视频广告
  bool shouldPlayVideoAd() {
    // 先检查基本条件
    if (!Config.adOn || _adData == null) {
      LogUtil.i('广告功能已关闭或无数据，不需要播放视频广告');
      return false;
    }
    
    // 检查是否已在当前频道触发过视频广告
    if (_hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('当前频道已触发视频广告，不重复播放');
      return false;
    }
    
    // 检查是否有其他类型广告在显示
    if (_isShowingTextAd || _isShowingImageAd || _isShowingVideoAd) {
      LogUtil.i('已有其他广告显示中，不播放视频广告');
      return false;
    }
    
    // 选择下一个要播放的广告
    final nextAd = _selectNextAd(_adData!.videoAds);
    if (nextAd == null) {
      LogUtil.i('没有可播放的视频广告');
      return false;
    }
    
    // 缓存将要播放的广告
    _currentVideoAd = nextAd;
    LogUtil.i('需要播放视频广告: ${nextAd.id}');
    return true;
  }

  // 播放视频广告方法
  Future<void> playVideoAd() async {
    // 再次检查基本条件
    if (!Config.adOn || _currentVideoAd == null) {
      LogUtil.i('广告功能已关闭或无视频广告，跳过播放');
      return;
    }
    
    final videoAd = _currentVideoAd!;
    LogUtil.i('开始播放视频广告: ${videoAd.url}');
    
    // 标记状态
    _isShowingVideoAd = true;
    _hasTriggeredVideoAdOnCurrentChannel = true;
    notifyListeners();
    
    // 创建异步完成器
    final adCompletion = Completer<void>();

    try {
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: videoAd.url!,
        isHls: _isHlsStream(videoAd.url),
      );
      
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: _isHlsStream(videoAd.url),
        eventListener: (event) => _videoAdEventListener(event, adCompletion),
      );

      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();

      // 等待广告播放完成或超时
      await adCompletion.future.timeout(
        Duration(seconds: VIDEO_AD_TIMEOUT_SECONDS), 
        onTimeout: () {
          LogUtil.i('广告播放超时，默认结束');
          _cleanupAdController();
          if (!adCompletion.isCompleted) {
            adCompletion.complete();
          }
        }
      );
    } catch (e) {
      LogUtil.e('视频广告播放失败: $e');
      _cleanupAdController();
      if (!adCompletion.isCompleted) {
        adCompletion.completeError(e);
      }
    } finally {
      // 更新计数
      _adShownCounts[videoAd.id] = (_adShownCounts[videoAd.id] ?? 0) + 1;
      
      _isShowingVideoAd = false;
      _currentVideoAd = null;
      
      LogUtil.i('广告播放结束，次数更新: ${_adShownCounts[videoAd.id]} / ${videoAd.displayCount}');
      notifyListeners();
      
      // 视频广告结束后，可以考虑安排其他类型广告
      _schedulePostVideoAds();
    }
  }

  // [修改] 视频广告结束后安排其他广告 - 只安排文字广告，不安排图片广告
  void _schedulePostVideoAds() {
    // 使用延迟确保UI已更新
    Timer(const Duration(milliseconds: 1000), () {
      // 视频广告结束后，只检查是否可以显示文字广告，不安排图片广告
      if (!_hasTriggeredTextAdOnCurrentChannel) {
        LogUtil.i('视频广告结束，安排文字广告');
        _scheduleTextAd();
      } else {
        LogUtil.i('视频广告结束，但文字广告已触发，不再安排其他广告');
      }
    });
  }

  // 视频广告事件监听器
  void _videoAdEventListener(BetterPlayerEvent event, Completer<void> completer) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      if (!completer.isCompleted) {
        completer.complete(); // 完成 Future，表示广告播放结束
      }
    }
  }

  // 清理视频广告控制器
  void _cleanupAdController() {
    if (_adController != null) {
      _adController!.dispose();
      _adController = null;
    }
  }

  // 重置广告状态
  void reset({bool rescheduleAds = true, bool preserveTimers = false}) {
    // 记录当前频道，用于后续可能的重新调度
    final currentChannelId = _lastChannelId;
    
    // 清理视频广告控制器
    _cleanupAdController();
    
    // 视频广告标记
    _isShowingVideoAd = false;
    _currentVideoAd = null;
    
    // 根据需要处理定时器
    if (!preserveTimers) {
      _cancelAllAdTimers();
    }
    
    // 停止当前显示的广告
    if (_isShowingTextAd) {
      // [修改] 使用Marquee后不再需要手动处理动画控制器
      _isShowingTextAd = false;
      _currentTextAd = null;
    }
    
    if (_isShowingImageAd) {
      _isShowingImageAd = false;
      _currentImageAd = null;
      _imageAdRemainingSeconds = 0;
      imageAdCountdownNotifier.value = 0;
    }
    
    LogUtil.i('广告管理器状态已重置，重新安排广告: $rescheduleAds, 保留计时器: $preserveTimers');
    
    // 更新UI
    notifyListeners();
    
    // 只有在需要且有频道ID时才重新调度
    if (rescheduleAds && currentChannelId != null && _adData != null) {
      // 使用延迟来避免频繁重置导致的重复调度
      Timer(const Duration(milliseconds: MIN_RESCHEDULE_INTERVAL_MS), () {
        // 确保频道ID没有变化
        if (_lastChannelId == currentChannelId) {
          _scheduleAdsForNewChannel();
        }
      });
    }
  }

  // 显式释放所有资源
  @override
  void dispose() {
    _cleanupAdController();
    
    // [修改] 不再需要处理文字广告动画控制器
    
    // 取消所有定时器
    _cancelAllAdTimers();
    
    _isShowingTextAd = false;
    _isShowingImageAd = false;
    _isShowingVideoAd = false;
    _currentTextAd = null;
    _currentImageAd = null;
    _currentVideoAd = null;
    _adData = null;
    _vsyncProvider = null;
    
    LogUtil.i('广告管理器资源已释放');
    
    super.dispose();
  }

  // 状态查询方法
  bool getShowTextAd() {
    final show = _isShowingTextAd && 
                _currentTextAd != null && 
                _currentTextAd!.content != null && 
                Config.adOn;
    
    // 日志记录帮助调试
    if (_isShowingTextAd && !show) {
      LogUtil.i('文字广告条件检查: _isShowingTextAd=$_isShowingTextAd, ' +
        '_currentTextAd=${_currentTextAd != null}, ' +
        'content=${_currentTextAd?.content != null}, ' +
        'Config.adOn=${Config.adOn}');
    }
    
    return show;
  }

  bool getShowImageAd() => _isShowingImageAd && _currentImageAd != null && Config.adOn;

  // 数据访问方法
  String? getTextAdContent() => _currentTextAd?.content;
  String? getTextAdLink() => _currentTextAd?.link;
  AdItem? getCurrentImageAd() => _isShowingImageAd ? _currentImageAd : null;
  BetterPlayerController? getAdController() => _adController;
  
  // [修改] 文字广告 Widget - 修改onDone回调以避免UI闪烁
  Widget buildTextAdWidget() {
    if (!getShowTextAd() || _currentTextAd?.content == null) {
      return const SizedBox.shrink(); // 返回空组件
    }
    
    final content = getTextAdContent()!;
    // 根据屏幕方向确定位置
    final double topPosition = _isLandscape ? 
                   TEXT_AD_TOP_POSITION_LANDSCAPE : 
                   TEXT_AD_TOP_POSITION_PORTRAIT;
    
    return Positioned(
      top: topPosition,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          if (_currentTextAd?.link != null && _currentTextAd!.link!.isNotEmpty) {
            handleAdClick(_currentTextAd!.link);
          }
        },
        child: Container(
          width: double.infinity,
          height: TEXT_AD_FONT_SIZE * 1.5, // 固定高度以防止文字换行
          color: Colors.black.withOpacity(0.5), // 保留原半透明背景
          child: Marquee(
            text: content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: TEXT_AD_FONT_SIZE,
              shadows: [
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 0.5,
                  color: Colors.black
                )
              ],
            ),
            scrollAxis: Axis.horizontal,              // 水平滚动
            crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
            velocity: TEXT_AD_SCROLL_VELOCITY,        // 滚动速度
            blankSpace: _screenWidth,                 // 文本之间的空白距离设置为屏幕宽度，确保完全滚出后才开始下一次
            startPadding: _screenWidth,               // 初始填充设置为屏幕宽度，确保从屏幕右侧开始
            accelerationDuration: Duration.zero,      // 无加速时间
            decelerationDuration: Duration.zero,      // 无减速时间
            accelerationCurve: Curves.linear,         // 线性加速曲线
            decelerationCurve: Curves.linear,         // 线性减速曲线
            numberOfRounds: TEXT_AD_REPETITIONS,      // 使用定义的循环次数常量
            pauseAfterRound: Duration.zero,           // 每轮之间无暂停
            showFadingOnlyWhenScrolling: false,       // 始终不显示渐变效果
            fadingEdgeStartFraction: 0.0,             // 无开始渐变
            fadingEdgeEndFraction: 0.0,               // 无结束渐变
            onDone: () {
              // [修改] 延迟状态更新以避免UI闪烁，防止影响其他元素
              LogUtil.i('文字广告完成所有循环');
              _isShowingTextAd = false;
              _currentTextAd = null;
              
              // 使用延迟微任务确保不会干扰当前帧的渲染
              WidgetsBinding.instance.addPostFrameCallback((_) {
                notifyListeners();
              });
            },
          ),
        ),
      ),
    );
  }
  
  // [修改] 图片广告 Widget - 重新设计为弹出样式，不使用全屏半透明遮罩
  Widget buildImageAdWidget() {
    if (!getShowImageAd() || _currentImageAd == null) {
      return const SizedBox.shrink(); // 返回空组件
    }
    
    final imageAd = _currentImageAd!;
    
    // 计算合适的广告尺寸
    double maxWidth = _screenWidth * 0.8;
    double maxHeight = _isLandscape ? 
                      _screenHeight * 0.7 : 
                      (_screenWidth / (16 / 9)) * 0.7; // 根据屏幕方向调整最大高度
    
    // 使用Material包装确保视觉效果一致
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                spreadRadius: 5,
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏 - 只显示"推广内容"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    '推广内容',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                
                // 广告内容
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (imageAd.url != null && imageAd.url!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageAd.url!,
                                fit: BoxFit.contain,
                                // 根据设置的最大尺寸约束图片
                                width: maxWidth * 0.9,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: _isLandscape ? 200 : 140, // 根据横竖屏调整错误占位符高度
                                  width: maxWidth * 0.9,
                                  color: Colors.grey[900],
                                  child: const Center(
                                    child: Text(
                                      '广告加载失败',
                                      style: TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // 底部控制栏
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // 左侧显示倒计时提示
                                const Text(
                                  '广告关闭倒计时',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                
                                // 中间显示倒计时数字（红色）
                                ValueListenableBuilder<int>(
                                  valueListenable: imageAdCountdownNotifier,
                                  builder: (context, remainingSeconds, child) {
                                    return Text(
                                      '$remainingSeconds',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                                
                                // 右侧显示了解更多按钮
                                if (imageAd.link != null && imageAd.link!.isNotEmpty)
                                  ElevatedButton(
                                    onPressed: () {
                                      handleAdClick(imageAd.link);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('了解更多', style: TextStyle(fontSize: 14)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 处理广告点击
  Future<void> handleAdClick(String? link) async {
    if (link == null || link.isEmpty) {
      LogUtil.i('广告链接为空，不执行点击操作');
      return;
    }
    
    try {
      final uri = Uri.parse(link);
      
      // 尝试启动链接
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

  // 判断是否为 HLS 流
  bool _isHlsStream(String? url) {
    return url != null && url.toLowerCase().contains('.m3u8');
  }
  
  // 获取两个数值中的较小值
  double min(double a, double b) => a < b ? a : b;
}
