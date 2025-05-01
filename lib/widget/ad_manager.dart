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
    
    return adsList.map((item) {
      // 验证必要字段
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
    }).whereType<AdItem>().toList(); // 过滤无效项
  }

  factory AdData.fromJson(Map<String, dynamic> json) {
    // 解析JSON数据为广告模型
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
  
  // 判断广告数据是否为空
  bool get isEmpty => textAds.isEmpty && videoAds.isEmpty && imageAds.isEmpty;
}

// 广告计数管理辅助类
class AdCountManager {
  // 获取广告展示次数
  static Future<Map<String, int>> loadAdCounts() async => {};

  // 保存广告展示次数
  static Future<void> saveAdCounts(Map<String, int> counts) async {}

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
  static const double TEXT_AD_TOP_POSITION_LANDSCAPE = 8.0; // 横屏文字广告距顶部距离
  static const double TEXT_AD_TOP_POSITION_PORTRAIT = 10.0; // 竖屏文字广告距顶部距离

  // 时间相关常量
  static const int MIN_RESCHEDULE_INTERVAL_MS = 2000; // 最小重新调度间隔
  static const int CHANNEL_CHANGE_DELAY_MS = 500; // 频道切换后延迟
  static const int DEFAULT_IMAGE_AD_DURATION = 8; // 默认图片广告时长
  static const int DEFAULT_TEXT_AD_DELAY = 10; // 默认文字广告延迟
  static const int DEFAULT_IMAGE_AD_DELAY = 20; // 默认图片广告延迟
  static const int VIDEO_AD_TIMEOUT_SECONDS = 36; // 视频广告超时时间

  AdData? _adData; // 广告数据
  Map<String, int> _adShownCounts = {}; // 广告展示次数
  
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

  AdManager() {
    _init(); // 初始化广告管理器
  }

  // 初始化广告管理器
  Future<void> _init() async {
    _adShownCounts = {};
    await loadAdData();
  }

  // 更新屏幕信息并触发UI更新
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
      
      if (_isShowingTextAd && _currentTextAd != null) {
        notifyListeners(); // 通知文字广告UI更新
      }
      
      notifyListeners();
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
    
    if (_isShowingTextAd || _isShowingImageAd) {
      _stopAllDisplayingAds(); // 停止正在显示的广告
    }
    
    if (_adData != null && Config.adOn) {
      Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
        if (_lastChannelId == channelId) {
          _scheduleAdsForNewChannel(); // 延迟调度新频道广告
        }
      });
    }
  }
  
  // 取消所有广告定时器
  void _cancelAllAdTimers() {
    _textAdTimers.values.forEach((timer) => timer.cancel());
    _textAdTimers.clear();
    _imageAdTimers.values.forEach((timer) => timer.cancel());
    _imageAdTimers.clear();
  }
  
  // 停止所有正在显示的广告
  void _stopAllDisplayingAds() {
    if (_isShowingTextAd) {
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
  
  // 为新频道安排广告，按优先级调度
  void _scheduleAdsForNewChannel() {
    if (_adData == null) return;
    
    AdItem? nextVideoAd;
    AdItem? nextImageAd;
    AdItem? nextTextAd;
    
    if (!_hasTriggeredVideoAdOnCurrentChannel) {
      nextVideoAd = _selectNextAd(_adData!.videoAds); // 检查可用视频广告
    }
    
    if (!_hasTriggeredImageAdOnCurrentChannel) {
      nextImageAd = _selectNextAd(_adData!.imageAds); // 检查可用图片广告
    }
    
    if (!_hasTriggeredTextAdOnCurrentChannel) {
      nextTextAd = _selectNextAd(_adData!.textAds); // 检查可用文字广告
    }
    
    LogUtil.i('为新频道安排广告，可用广告: 视频=${nextVideoAd != null}, 图片=${nextImageAd != null}, 文字=${nextTextAd != null}');
    
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

  // 按类型调度广告
  void _scheduleAdByType(String adType) {
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
        defaultDelay = DEFAULT_IMAGE_AD_DURATION;
        showAdFunc = _showImageAd;
        break;
      default:
        LogUtil.e('未知广告类型: $adType');
        return;
    }
    
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不安排$logPrefix');
      return;
    }
    
    if (hasTriggered) {
      LogUtil.i('当前频道已触发$logPrefix，不重复安排');
      return;
    }
    
    if (otherAdShowing) {
      LogUtil.i('已有其他广告显示中，不安排$logPrefix，等待其结束');
      return;
    }
    
    if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('当前频道已播放视频广告，不显示图片广告');
      return;
    }
    
    final now = DateTime.now();
    if (_lastAdScheduleTimes.containsKey(adType)) {
      final timeSinceLastSchedule = now.difference(_lastAdScheduleTimes[adType]!).inMilliseconds;
      if (timeSinceLastSchedule < MIN_RESCHEDULE_INTERVAL_MS) {
        LogUtil.i('$logPrefix调度过于频繁，间隔仅 $timeSinceLastSchedule ms，最小需要 $MIN_RESCHEDULE_INTERVAL_MS ms');
        return;
      }
    }
    
    final nextAd = _selectNextAd(adsList);
    if (nextAd == null) {
      LogUtil.i('没有可显示的$logPrefix');
      if (adType == 'text' && !_hasTriggeredImageAdOnCurrentChannel && 
          !_isShowingImageAd && !_hasTriggeredVideoAdOnCurrentChannel) {
        _scheduleImageAd(); // 无文字广告时尝试调度图片广告
      }
      return;
    }
    
    _lastAdScheduleTimes[adType] = now;
    final delaySeconds = nextAd.displayDelaySeconds ?? defaultDelay;
    LogUtil.i('安排$logPrefix ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    final timerId = '${adType}_${nextAd.id}_${now.millisecondsSinceEpoch}';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    
    timersMap[timerId] = Timer(Duration(seconds: delaySeconds), () {
      if (!Config.adOn || (adType == 'text' && _hasTriggeredTextAdOnCurrentChannel) || 
          (adType == 'image' && _hasTriggeredImageAdOnCurrentChannel)) {
        LogUtil.i('延迟显示$logPrefix时条件已变化，取消显示');
        timersMap.remove(timerId);
        return;
      }
      
      if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
        LogUtil.i('延迟期间检测到视频广告已播放，取消图片广告');
        timersMap.remove(timerId);
        return;
      }
      
      if (_isShowingVideoAd || _isShowingImageAd || _isShowingTextAd) {
        LogUtil.i('其他广告正在显示，等待其结束再显示$logPrefix');
        _createAdWaitingTimer(adType, nextAd, timerId); // 创建等待定时器
        return;
      }
      
      showAdFunc(nextAd);
      timersMap.remove(timerId);
    });
  }
  
  // 创建广告等待定时器
  void _createAdWaitingTimer(String adType, AdItem ad, String timerId) {
    final waitTimerId = 'wait_$timerId';
    final Map<String, Timer> timersMap = adType == 'text' ? _textAdTimers : _imageAdTimers;
    
    timersMap[waitTimerId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingImageAd && !_isShowingTextAd && !_isShowingVideoAd) {
        timer.cancel();
        timersMap.remove(waitTimerId);
        
        if (!Config.adOn || (adType == 'text' && _hasTriggeredTextAdOnCurrentChannel) || 
            (adType == 'image' && _hasTriggeredImageAdOnCurrentChannel)) {
          LogUtil.i('等待期间条件已变化，取消显示${adType == 'text' ? '文字广告' : '图片广告'}');
          return;
        }
        
        if (adType == 'image' && _hasTriggeredVideoAdOnCurrentChannel) {
          LogUtil.i('等待期间检测到视频广告已播放，取消图片广告');
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
  
  // 文字广告调度接口方法
  void _scheduleTextAd() {
    _scheduleAdByType('text');
  }

  // 文字广告调度接口方法
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
    notifyListeners();
  }

  // 显示图片广告
  void _showImageAd(AdItem ad) {
    _currentImageAd = ad;
    _isShowingImageAd = true;
    _adShownCounts[ad.id] = (_adShownCounts[ad.id] ?? 0) + 1;
    _hasTriggeredImageAdOnCurrentChannel = true;
    
    _imageAdRemainingSeconds = ad.durationSeconds ?? DEFAULT_IMAGE_AD_DURATION;
    imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
    
    LogUtil.i('显示图片广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners();
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
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        notifyListeners();
        
        if (!_hasTriggeredTextAdOnCurrentChannel && _adData != null) {
          LogUtil.i('图片广告结束，安排文字广告');
          _scheduleTextAd();
        } else {
          LogUtil.i('图片广告结束，无需安排文字广告');
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    });
  }
  
  // 更新文字广告动画
  void _updateTextAdAnimation() {
    LogUtil.i('文字广告动画已启动，循环 $TEXT_AD_REPETITIONS 次');
    notifyListeners();
  }

  // 随机选择下一个广告
  AdItem? _selectNextAd(List<AdItem> candidates) {
    if (candidates.isEmpty) return null;
    
    if (!Config.adOn) {
      LogUtil.i('广告功能已全局关闭');
      return null;
    }
    
    final validAds = candidates.where((ad) => 
      ad.enabled && 
      (_adShownCounts[ad.id] ?? 0) < ad.displayCount
    ).toList();
    
    if (validAds.isEmpty) return null;
    
    validAds.shuffle();
    return validAds.first;
  }
  
  // 构建带时间戳的API URL
  String _buildApiUrl(String baseUrl) {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return _addTimestampToUrl(baseUrl, timestamp);
  }

  // 加载广告数据
  Future<bool> loadAdData() async {
    if (_isLoadingAdData) {
      if (_adDataLoadedCompleter != null) {
        return _adDataLoadedCompleter!.future; // 等待正在进行的加载
      }
    }
    
    _isLoadingAdData = true;
    _adDataLoadedCompleter = Completer<bool>();
    
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不加载广告数据');
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
    
    try {
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
        LogUtil.i('广告数据加载成功: 文字广告: ${adData.textAds.length}个, 视频广告: ${adData.videoAds.length}个, 图片广告: ${adData.imageAds.length}个');
        
        if (_lastChannelId != null) {
          _scheduleAdsForNewChannel(); // 安排广告显示
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
      final response = await HttpUtil().getRequest(
        url,
        parseData: (data) {
          if (data is! Map<String, dynamic>) {
            LogUtil.e('广告数据格式不正确，期望 JSON 对象，实际为: $data');
            return null;
          }
          
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

  // 为URL添加时间戳参数
  String _addTimestampToUrl(String originalUrl, String timestamp) {
    try {
      final uri = Uri.parse(originalUrl);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams['t'] = timestamp;
      
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        path: uri.path,
        queryParameters: queryParams,
        port: uri.port,
      ).toString();
    } catch (e) {
      LogUtil.e('添加时间戳到URL失败: $e，返回原始URL');
      if (originalUrl.contains('?')) {
        return '$originalUrl&t=$timestamp';
      } else {
        return '$originalUrl?t=$timestamp';
      }
    }
  }

  // 异步检查是否需要播放视频广告
  Future<bool> shouldPlayVideoAdAsync() async {
    if (_adData == null && !_isLoadingAdData) {
      await loadAdData();
    } else if (_adData == null && _isLoadingAdData && _adDataLoadedCompleter != null) {
      await _adDataLoadedCompleter!.future;
    }
    
    return shouldPlayVideoAd();
  }

  // 判断是否需要播放视频广告
  bool shouldPlayVideoAd() {
    if (!Config.adOn || _adData == null) {
      LogUtil.i('广告功能已关闭或无数据，不需要播放视频广告');
      return false;
    }
    
    if (_hasTriggeredVideoAdOnCurrentChannel) {
      LogUtil.i('当前频道已触发视频广告，不重复播放');
      return false;
    }
    
    if (_isShowingTextAd || _isShowingImageAd || _isShowingVideoAd) {
      LogUtil.i('已有其他广告显示中，不播放视频广告');
      return false;
    }
    
    final nextAd = _selectNextAd(_adData!.videoAds);
    if (nextAd == null) {
      LogUtil.i('没有可播放的视频广告');
      return false;
    }
    
    _currentVideoAd = nextAd;
    LogUtil.i('需要播放视频广告: ${nextAd.id}');
    return true;
  }

  // 播放视频广告
  Future<void> playVideoAd() async {
    if (!Config.adOn || _currentVideoAd == null) {
      LogUtil.i('广告功能已关闭或无视频广告，跳过播放');
      return;
    }
    
    final videoAd = _currentVideoAd!;
    LogUtil.i('开始播放视频广告: ${videoAd.url}');
    
    _isShowingVideoAd = true;
    _hasTriggeredVideoAdOnCurrentChannel = true;
    notifyListeners();
    
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
      _adShownCounts[videoAd.id] = (_adShownCounts[videoAd.id] ?? 0) + 1;
      _isShowingVideoAd = false;
      _currentVideoAd = null;
      
      LogUtil.i('广告播放结束，次数更新: ${_adShownCounts[videoAd.id]} / ${videoAd.displayCount}');
      notifyListeners();
      _schedulePostVideoAds(); // 安排后续广告
    }
  }

  // 视频广告结束后安排文字广告
  void _schedulePostVideoAds() {
    Timer(const Duration(milliseconds: 1000), () {
      if (!_hasTriggeredTextAdOnCurrentChannel) {
        LogUtil.i('视频广告结束，安排文字广告');
        _scheduleTextAd();
      } else {
        LogUtil.i('视频广告结束，无需安排文字广告');
      }
    });
  }

  // 监听视频广告播放事件
  void _videoAdEventListener(BetterPlayerEvent event, Completer<void> completer) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      if (!completer.isCompleted) {
        completer.complete();
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
    final currentChannelId = _lastChannelId;
    _cleanupAdController();
    
    _isShowingVideoAd = false;
    _currentVideoAd = null;
    
    if (!preserveTimers) {
      _cancelAllAdTimers();
    }
    
    if (_isShowingTextAd) {
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
    notifyListeners();
    
    if (rescheduleAds && currentChannelId != null && _adData != null) {
      Timer(const Duration(milliseconds: MIN_RESCHEDULE_INTERVAL_MS), () {
        if (_lastChannelId == currentChannelId) {
          _scheduleAdsForNewChannel();
        }
      });
    }
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
    _adData = null;
    _vsyncProvider = null;
    
    LogUtil.i('广告管理器资源已释放');
    super.dispose();
  }

  // 检查是否显示文字广告
  bool getShowTextAd() {
    final show = _isShowingTextAd && 
                _currentTextAd != null && 
                _currentTextAd!.content != null && 
                Config.adOn;
    
    if (_isShowingTextAd && !show) {
      LogUtil.i('文字广告条件检查: _isShowingTextAd=$_isShowingTextAd, ' +
        '_currentTextAd=${_currentTextAd != null}, ' +
        'content=${_currentTextAd?.content != null}, ' +
        'Config.adOn=${Config.adOn}');
    }
    
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
    if (!getShowTextAd() || _currentTextAd?.content == null) {
      return const SizedBox.shrink();
    }
    
    final content = getTextAdContent()!;
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
          height: TEXT_AD_FONT_SIZE * 1.5,
          color: Colors.black.withOpacity(0.5),
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
            onDone: () {
              LogUtil.i('文字广告完成所有循环');
              _isShowingTextAd = false;
              _currentTextAd = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                notifyListeners();
              });
            },
          ),
        ),
      ),
    );
  }
  
  // 构建图片广告Widget
  Widget buildImageAdWidget() {
    if (!getShowImageAd() || _currentImageAd == null) {
      return const SizedBox.shrink();
    }
    
    final imageAd = _currentImageAd!;
    
    // 计算初始最大尺寸约束（与原代码一致，作为默认值）
    double maxWidth = _screenWidth * 0.85;
    double maxHeight = _isLandscape ? 
                    _screenHeight * 0.8 : 
                    (_screenWidth / (16 / 9)) * 0.75;
    
    // 使用FutureBuilder先获取图片尺寸，再据此调整弹窗尺寸
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: FutureBuilder<Size?>(
          // 预加载图片以获取其实际尺寸
          future: _getImageSize(imageAd.url),
          builder: (context, snapshot) {
            // 如果图片信息加载完成，根据图片原始尺寸计算合适的宽高
            if (snapshot.connectionState == ConnectionState.done && 
                snapshot.hasData && 
                snapshot.data != null) {
              final imageSize = snapshot.data!;
              final imageWidth = imageSize.width;
              final imageHeight = imageSize.height;
              
              // 计算图片宽高比
              final aspectRatio = imageWidth / imageHeight;
              
              // 根据屏幕尺寸和图片比例计算最适合的显示尺寸
              if (aspectRatio > 1) {
                // 横向图片，先确定宽度，再按比例计算高度
                maxWidth = min(_screenWidth * 0.85, imageWidth);
                maxHeight = min(maxWidth / aspectRatio, _screenHeight * 0.85);
              } else {
                // 纵向图片，先确定高度，再按比例计算宽度
                maxHeight = min(_screenHeight * 0.85, imageHeight);
                maxWidth = min(maxHeight * aspectRatio, _screenWidth * 0.85);
              }
              
              LogUtil.i('图片广告尺寸调整: 原始尺寸=${imageWidth}x${imageHeight}, ' +
                      '调整后=${maxWidth}x${maxHeight}, 宽高比=$aspectRatio');
            } else if (snapshot.hasError) {
              // 图片加载出错时记录日志
              LogUtil.e('获取图片尺寸失败: ${snapshot.error}');
            }
            
            // 继续构建弹窗UI（与原代码基本保持一致）
            return Container(
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade800,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '推广内容',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                '广告关闭倒计时: ',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              ValueListenableBuilder<int>(
                                valueListenable: imageAdCountdownNotifier,
                                builder: (context, remainingSeconds, child) {
                                  return Text(
                                    '$remainingSeconds秒',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (imageAd.link != null && imageAd.link!.isNotEmpty) {
                            handleAdClick(imageAd.link);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: imageAd.url != null && imageAd.url!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageAd.url!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    height: _isLandscape ? 200 : 140,
                                    width: double.infinity,
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: Text(
                                        '广告加载失败',
                                        style: TextStyle(color: Colors.white70, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 获取网络图片尺寸的辅助方法
  Future<Size?> _getImageSize(String? imageUrl) async {
    // 如果URL为空，返回null使用默认尺寸
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    
    final Completer<Size?> completer = Completer();
    
    // 创建图片加载对象
    final imageProvider = NetworkImage(imageUrl);
    final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
    
    // 添加图片加载监听
    final listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final image = info.image;
        if (!completer.isCompleted) {
          completer.complete(Size(
            image.width.toDouble(), 
            image.height.toDouble()
          ));
        }
      },
      onError: (exception, stackTrace) {
        if (!completer.isCompleted) {
          LogUtil.e('加载图片失败: $exception');
          completer.completeError(exception);
        }
      }
    );
    
    stream.addListener(listener);
    
    // 设置超时处理，避免长时间等待
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        stream.removeListener(listener);
        LogUtil.i('获取图片尺寸超时，使用默认尺寸');
        completer.complete(null);
      }
    });
    
    // 确保在Future完成后移除监听，避免内存泄漏
    return completer.future.whenComplete(() {
      stream.removeListener(listener);
    });
  }

  // 处理广告点击跳转
  Future<void> handleAdClick(String? link) async {
    if (link == null || link.isEmpty) {
      LogUtil.i('广告链接为空，不执行点击操作');
      return;
    }
    
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
  
  // 返回两个数值中的较小值
  double min(double a, double b) => a < b ? a : b;
}
