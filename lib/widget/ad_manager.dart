import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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

  AdItem({
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

  AdData({
    required this.textAds,
    required this.videoAds,
    required this.imageAds,
  });

  factory AdData.fromJson(Map<String, dynamic> json) {
    // 直接处理根级数据
    final data = json;
    
    // 解析文字广告列表
    List<AdItem> parseTextAds() {
      if (data.containsKey('text_ads') && data['text_ads'] is List) {
        return (data['text_ads'] as List).map((item) => AdItem(
          id: item['id'] ?? 'text_${DateTime.now().millisecondsSinceEpoch}',
          content: item['content'],
          enabled: item['enabled'] ?? false,
          displayCount: item['display_count'] ?? 0,
          displayDelaySeconds: item['display_delay_seconds'],
          link: item['link'],
          type: 'text',
        )).toList();
      }
      return [];
    }
    
    // 解析视频广告列表
    List<AdItem> parseVideoAds() {
      if (data.containsKey('video_ads') && data['video_ads'] is List) {
        return (data['video_ads'] as List).map((item) => AdItem(
          id: item['id'] ?? 'video_${DateTime.now().millisecondsSinceEpoch}',
          url: item['url'],
          enabled: item['enabled'] ?? false,
          displayCount: item['display_count'] ?? 0,
          link: item['link'],
          type: 'video',
        )).toList();
      }
      return [];
    }
    
    // 解析图片广告列表
    List<AdItem> parseImageAds() {
      if (data.containsKey('image_ads') && data['image_ads'] is List) {
        return (data['image_ads'] as List).map((item) => AdItem(
          id: item['id'] ?? 'image_${DateTime.now().millisecondsSinceEpoch}',
          url: item['url'],
          enabled: item['enabled'] ?? false,
          displayCount: item['display_count'] ?? 0,
          displayDelaySeconds: item['display_delay_seconds'],
          durationSeconds: item['duration_seconds'] ?? 8,
          link: item['link'],
          type: 'image',
        )).toList();
      }
      return [];
    }

    return AdData(
      textAds: parseTextAds(),
      videoAds: parseVideoAds(),
      imageAds: parseImageAds(),
    );
  }
}

// 广告计数管理辅助类
class AdCountManager {
  // 加载广告已显示次数
  static Future<Map<String, int>> loadAdCounts() async {
    await SpUtil.getInstance();
    String? countsJson = SpUtil.getString(Config.adCountsKey);
    if (countsJson != null && countsJson.isNotEmpty) {
      try {
        Map<String, dynamic> data = jsonDecode(countsJson);
        return data.map((key, value) => MapEntry(key, value as int));
      } catch (e) {
        LogUtil.e('加载广告计数失败: $e');
      }
    }
    return {};
  }

  // 保存广告已显示次数
  static Future<void> saveAdCounts(Map<String, int> counts) async {
    await SpUtil.getInstance();
    await SpUtil.putString(Config.adCountsKey, jsonEncode(counts));
  }

  // 增加广告显示次数
  static Future<void> incrementAdCount(String adId, Map<String, int> counts) async {
    counts[adId] = (counts[adId] ?? 0) + 1;
    await saveAdCounts(counts);
  }
}

// 广告管理类
class AdManager with ChangeNotifier {
  // 文字广告相关常量
  static const int TEXT_AD_SCROLL_DURATION_SECONDS = 15; // 文字广告滚动持续时间（秒）
  static const double TEXT_AD_FONT_SIZE = 16.0; // 文字广告字体大小
  
  // 广告位置常量
  static const double TEXT_AD_TOP_POSITION_LANDSCAPE = 50.0; // 文字广告在横屏模式下的顶部位置
  static const double TEXT_AD_TOP_POSITION_PORTRAIT = 80.0; // 文字广告在竖屏模式下的顶部位置

  // 新增常量
  static const int MIN_RESCHEDULE_INTERVAL_MS = 2000; // 最小重新调度间隔
  static const int CHANNEL_CHANGE_DELAY_MS = 500;    // 频道切换后延迟调度

  AdData? _adData; // 广告数据
  Map<String, int> _adShownCounts = {}; // 各广告已显示次数
  
  // 修改：使用独立的广告类型触发标志
  bool _hasTriggeredTextAdOnCurrentChannel = false;
  bool _hasTriggeredImageAdOnCurrentChannel = false;
  bool _hasTriggeredVideoAdOnCurrentChannel = false;
  
  // 当前显示状态
  bool _isShowingTextAd = false;
  bool _isShowingImageAd = false;
  bool _isShowingVideoAd = false;
  
  // 当前显示的广告
  AdItem? _currentTextAd;
  AdItem? _currentImageAd;
  AdItem? _currentVideoAd;
  
  String? _lastChannelId; // 记录上次频道ID，用于检测频道切换
  
  // 修改：分离不同类型广告的计时器，方便个别管理
  Map<String, Timer?> _textAdTimers = {};
  Map<String, Timer?> _imageAdTimers = {};
  
  // 新增：时间追踪，避免频繁调度
  Map<String, DateTime> _lastAdScheduleTimes = {};
  
  // 视频广告控制器
  BetterPlayerController? _adController;
  
  // 文字广告动画控制
  AnimationController? _textAdAnimationController;
  Animation<double>? _textAdAnimation;
  
  // 图片广告倒计时相关
  int _imageAdRemainingSeconds = 0;
  final ValueNotifier<int> imageAdCountdownNotifier = ValueNotifier<int>(0);

  // 添加广告数据加载状态
  bool _isLoadingAdData = false;
  // 添加广告加载完成的Completer
  Completer<bool>? _adDataLoadedCompleter;

  AdManager() {
    _init();
  }

  // 初始化
  Future<void> _init() async {
    // 加载广告计数
    _adShownCounts = await AdCountManager.loadAdCounts();
    // 初始加载广告数据
    loadAdData();
  }
  
  // 修改：改进频道切换处理
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
    // 这样可以避免频繁切换导致的资源浪费
    if (_adData != null && Config.adOn) {
      Timer(Duration(milliseconds: CHANNEL_CHANGE_DELAY_MS), () {
        // 再次确认频道未变化
        if (_lastChannelId == channelId) {
          _scheduleAdsForNewChannel();
        }
      });
    }
  }
  
  // 新增：取消所有广告计时器
  void _cancelAllAdTimers() {
    for (var timer in _textAdTimers.values) {
      timer?.cancel();
    }
    _textAdTimers.clear();
    
    for (var timer in _imageAdTimers.values) {
      timer?.cancel();
    }
    _imageAdTimers.clear();
  }
  
  // 新增：停止所有正在显示的广告
  void _stopAllDisplayingAds() {
    if (_isShowingTextAd) {
      _textAdAnimationController?.stop();
      _textAdAnimationController?.reset();
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
  
  // 新增：为新频道安排广告
  void _scheduleAdsForNewChannel() {
    // 优先视频广告 - 但不主动安排，由播放器决定何时检查和播放
    
    // 其次安排文字广告
    _scheduleTextAd();
    
    // 最后安排图片广告（条件性调度以避免冲突）
    // 只有当没有文字广告可显示时才安排图片广告
    if (!_hasTriggeredTextAdOnCurrentChannel && 
        !_isSchedulingTextAd() && 
        _selectNextAd(_adData!.textAds) == null) {
      _scheduleImageAd();
    }
  }
  
  // 新增：检查是否有文字广告正在调度中
  bool _isSchedulingTextAd() {
    return _textAdTimers.values.any((timer) => timer?.isActive == true);
  }
  
  // 修改：改进的文字广告调度方法
  void _scheduleTextAd() {
    // 检查基本条件
    if (!Config.adOn || _adData == null) {
      LogUtil.i('广告功能已关闭或无数据，不安排文字广告');
      return;
    }
    
    // 检查是否已经触发
    if (_hasTriggeredTextAdOnCurrentChannel) {
      LogUtil.i('当前频道已触发文字广告，不重复安排');
      return;
    }
    
    // 检查是否正在显示
    if (_isShowingTextAd || _isShowingVideoAd) {
      LogUtil.i('已有广告显示中，不安排文字广告');
      return;
    }
    
    // 检查调度时间间隔
    final now = DateTime.now();
    if (_lastAdScheduleTimes.containsKey('text')) {
      final timeSinceLastSchedule = now.difference(_lastAdScheduleTimes['text']!).inMilliseconds;
      if (timeSinceLastSchedule < MIN_RESCHEDULE_INTERVAL_MS) {
        LogUtil.i('文字广告调度过于频繁，间隔仅 $timeSinceLastSchedule ms，最小需要 $MIN_RESCHEDULE_INTERVAL_MS ms');
        return;
      }
    }
    
    // 选择下一个要显示的广告
    final nextAd = _selectNextAd(_adData!.textAds);
    if (nextAd == null) {
      LogUtil.i('没有可显示的文字广告');
      
      // 尝试安排图片广告作为替代
      if (!_hasTriggeredImageAdOnCurrentChannel && !_isShowingImageAd) {
        _scheduleImageAd();
      }
      return;
    }
    
    // 记录最后调度时间
    _lastAdScheduleTimes['text'] = now;
    
    // 使用广告指定的延迟时间
    final delaySeconds = nextAd.displayDelaySeconds ?? 10;
    LogUtil.i('安排文字广告 ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    // 创建定时器
    final timerId = 'text_${nextAd.id}_${now.millisecondsSinceEpoch}';
    _textAdTimers[timerId] = Timer(Duration(seconds: delaySeconds), () {
      // 延迟期满后再次检查条件
      if (!Config.adOn || _isShowingVideoAd || _hasTriggeredTextAdOnCurrentChannel) {
        LogUtil.i('延迟显示文字广告时条件已变化，取消显示');
        _textAdTimers.remove(timerId);
        return;
      }
      
      // 如果有图片广告在显示，等待其结束
      if (_isShowingImageAd) {
        LogUtil.i('图片广告正在显示，等待其结束再显示文字广告');
        // 创建一个检查器定时器，定期检查图片广告是否结束
        _createTextAdWaitingTimer(nextAd, timerId);
        return;
      }
      
      // 开始显示文字广告
      _showTextAd(nextAd);
      _textAdTimers.remove(timerId);
    });
  }
  
  // 新增：为文字广告创建等待定时器
  void _createTextAdWaitingTimer(AdItem ad, String timerId) {
    final waitTimerId = 'wait_$timerId';
    _textAdTimers[waitTimerId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingImageAd && !_isShowingVideoAd) {
        timer.cancel();
        _textAdTimers.remove(waitTimerId);
        
        // 再次检查条件
        if (!Config.adOn || _hasTriggeredTextAdOnCurrentChannel) {
          LogUtil.i('等待期间条件已变化，取消显示文字广告');
          return;
        }
        
        _showTextAd(ad);
      }
    });
  }
  
  // 新增：显示文字广告
  void _showTextAd(AdItem ad) {
    _currentTextAd = ad;
    _isShowingTextAd = true;
    _adShownCounts[ad.id] = (_adShownCounts[ad.id] ?? 0) + 1;
    AdCountManager.saveAdCounts(_adShownCounts);
    _hasTriggeredTextAdOnCurrentChannel = true;
    
    LogUtil.i('显示文字广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners();
  }

  // 修改：改进的图片广告调度方法
  void _scheduleImageAd() {
    // 检查基本条件
    if (!Config.adOn || _adData == null) {
      LogUtil.i('广告功能已关闭或无数据，不安排图片广告');
      return;
    }
    
    // 检查是否已经触发
    if (_hasTriggeredImageAdOnCurrentChannel) {
      LogUtil.i('当前频道已触发图片广告，不重复安排');
      return;
    }
    
    // 检查是否正在显示
    if (_isShowingImageAd || _isShowingVideoAd) {
      LogUtil.i('已有广告显示中，不安排图片广告');
      return;
    }
    
    // 检查调度时间间隔
    final now = DateTime.now();
    if (_lastAdScheduleTimes.containsKey('image')) {
      final timeSinceLastSchedule = now.difference(_lastAdScheduleTimes['image']!).inMilliseconds;
      if (timeSinceLastSchedule < MIN_RESCHEDULE_INTERVAL_MS) {
        LogUtil.i('图片广告调度过于频繁，间隔仅 $timeSinceLastSchedule ms，最小需要 $MIN_RESCHEDULE_INTERVAL_MS ms');
        return;
      }
    }
    
    // 选择下一个要显示的广告
    final nextAd = _selectNextAd(_adData!.imageAds);
    if (nextAd == null) {
      LogUtil.i('没有可显示的图片广告');
      return;
    }
    
    // 记录最后调度时间
    _lastAdScheduleTimes['image'] = now;
    
    // 使用广告指定的延迟时间
    final delaySeconds = nextAd.displayDelaySeconds ?? 20;
    LogUtil.i('安排图片广告 ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    // 创建定时器
    final timerId = 'image_${nextAd.id}_${now.millisecondsSinceEpoch}';
    _imageAdTimers[timerId] = Timer(Duration(seconds: delaySeconds), () {
      // 延迟期满后再次检查条件
      if (!Config.adOn || _isShowingVideoAd || _hasTriggeredImageAdOnCurrentChannel) {
        LogUtil.i('延迟显示图片广告时条件已变化，取消显示');
        _imageAdTimers.remove(timerId);
        return;
      }
      
      // 如果有文字广告在显示，等待其结束
      if (_isShowingTextAd) {
        LogUtil.i('文字广告正在显示，等待其结束再显示图片广告');
        // 创建一个检查器定时器，定期检查文字广告是否结束
        _createImageAdWaitingTimer(nextAd, timerId);
        return;
      }
      
      // 开始显示图片广告
      _showImageAd(nextAd);
      _imageAdTimers.remove(timerId);
    });
  }
  
  // 新增：为图片广告创建等待定时器
  void _createImageAdWaitingTimer(AdItem ad, String timerId) {
    final waitTimerId = 'wait_$timerId';
    _imageAdTimers[waitTimerId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isShowingTextAd && !_isShowingVideoAd) {
        timer.cancel();
        _imageAdTimers.remove(waitTimerId);
        
        // 再次检查条件
        if (!Config.adOn || _hasTriggeredImageAdOnCurrentChannel) {
          LogUtil.i('等待期间条件已变化，取消显示图片广告');
          return;
        }
        
        _showImageAd(ad);
      }
    });
  }
  
  // 新增：显示图片广告
  void _showImageAd(AdItem ad) {
    _currentImageAd = ad;
    _isShowingImageAd = true;
    _adShownCounts[ad.id] = (_adShownCounts[ad.id] ?? 0) + 1;
    AdCountManager.saveAdCounts(_adShownCounts);
    _hasTriggeredImageAdOnCurrentChannel = true;
    
    // 设置初始倒计时
    _imageAdRemainingSeconds = ad.durationSeconds ?? 8;
    imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
    
    LogUtil.i('显示图片广告 ${ad.id}, 当前次数: ${_adShownCounts[ad.id]} / ${ad.displayCount}');
    notifyListeners();
    
    // 设置自动关闭和倒计时
    _startImageAdCountdown(ad);
  }
  
  // 修改：改进的图片广告倒计时
  void _startImageAdCountdown(AdItem ad) {
    final duration = ad.durationSeconds ?? 8;
    _imageAdRemainingSeconds = duration;
    imageAdCountdownNotifier.value = duration;
    
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_imageAdRemainingSeconds <= 1) {
        timer.cancel();
        _isShowingImageAd = false;
        _currentImageAd = null;
        LogUtil.i('图片广告 ${ad.id} 自动关闭');
        notifyListeners();
        
        // 图片广告结束后，检查是否可以显示文字广告
        if (!_hasTriggeredTextAdOnCurrentChannel && _adData != null) {
          _scheduleTextAd();
        }
      } else {
        _imageAdRemainingSeconds--;
        imageAdCountdownNotifier.value = _imageAdRemainingSeconds;
      }
    });
  }
  
  // 初始化文字广告滚动动画（需在 Widget 中调用）
  void initTextAdAnimation(TickerProvider vsync, double screenWidth) {
    if (_textAdAnimationController == null && _currentTextAd?.content != null) {
      _textAdAnimationController = AnimationController(
        vsync: vsync,
        duration: Duration(seconds: TEXT_AD_SCROLL_DURATION_SECONDS),
      ); // 移除 repeat()，让动画只执行一次

      // 计算文字滚动的起始和结束位置
      final textWidth = _calculateTextWidth(_currentTextAd!.content!);
      _textAdAnimation = Tween<double>(
        begin: screenWidth, // 从屏幕右侧开始
        end: -textWidth,   // 滚动到文字完全移出左侧
      ).animate(_textAdAnimationController!);
      
      // 添加动画状态监听，在动画结束后隐藏广告
      _textAdAnimationController!.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _isShowingTextAd = false;
          _currentTextAd = null;
          notifyListeners();
          
          // 文字广告结束后，检查是否可以显示图片广告
          if (!_hasTriggeredImageAdOnCurrentChannel && _adData != null) {
            _scheduleImageAd();
          }
        }
      });
      
      // 开始动画
      _textAdAnimationController!.forward();
    }
  }

  // 更新文字广告动画（用于屏幕宽度变化时）
  void updateTextAdAnimation(double screenWidth) {
    if (_textAdAnimationController != null && _currentTextAd?.content != null) {
      final textWidth = _calculateTextWidth(_currentTextAd!.content!);
      _textAdAnimation = Tween<double>(
        begin: screenWidth,
        end: -textWidth,
      ).animate(_textAdAnimationController!);
      _textAdAnimationController!.forward(from: 0); // 重置动画
      notifyListeners();
    }
  }

  // 计算文字宽度（近似值）
  double _calculateTextWidth(String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: TEXT_AD_FONT_SIZE),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.width;
  }
  
  // 选择下一个显示的广告
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
    
    // 按已显示次数排序，优先显示次数少的
    validAds.sort((a, b) => 
      (_adShownCounts[a.id] ?? 0) - (_adShownCounts[b.id] ?? 0)
    );
    
    return validAds.first;
  }
  
  // 修改：改进广告加载方法
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
      // 首先尝试主API URL
      final response = await HttpUtil().getRequest(
        Config.adApiUrl,
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
      
      if (response != null) {
        _adData = response;
        LogUtil.i('广告数据加载成功: ${Config.adApiUrl}');
        LogUtil.i('文字广告: ${_adData!.textAds.length}个, 视频广告: ${_adData!.videoAds.length}个, 图片广告: ${_adData!.imageAds.length}个');
        
        // 为每种类型安排广告显示
        if (_lastChannelId != null) {
          _scheduleAdsForNewChannel();
        }
        
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(true);
        return true;
      } else {
        LogUtil.e('主API广告数据加载失败，尝试备用API');
        
        // 如果主API失败，尝试备用API
        if (Config.backupAdApiUrl.isNotEmpty) {
          final backupResponse = await HttpUtil().getRequest(
            Config.backupAdApiUrl,
            parseData: (data) {
              if (data is! Map<String, dynamic>) {
                LogUtil.e('备用API广告数据格式不正确，期望 JSON 对象，实际为: $data');
                return null;
              }
              
              // 只处理新格式的广告数据
              if (data.containsKey('text_ads') || data.containsKey('video_ads') || 
                  data.containsKey('image_ads')) {
                return AdData.fromJson(data);
              } else {
                LogUtil.e('备用API广告数据格式不符合预期');
                return null;
              }
            },
          );
          
          if (backupResponse != null) {
            _adData = backupResponse;
            LogUtil.i('备用API广告数据加载成功: ${Config.backupAdApiUrl}');
            LogUtil.i('文字广告: ${_adData!.textAds.length}个, 视频广告: ${_adData!.videoAds.length}个, 图片广告: ${_adData!.imageAds.length}个');
            
            // 为每种类型安排广告显示
            if (_lastChannelId != null) {
              _scheduleAdsForNewChannel();
            }
            
            _isLoadingAdData = false;
            _adDataLoadedCompleter!.complete(true);
            return true;
          }
        }
        
        _adData = null;
        LogUtil.e('广告数据加载失败，主API和备用API均返回null，可能服务器返回空响应或数据格式错误');
        _isLoadingAdData = false;
        _adDataLoadedCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      LogUtil.e('加载广告数据失败: $e');
      
      // 如果主API出现异常，尝试备用API
      if (Config.backupAdApiUrl.isNotEmpty) {
        try {
          LogUtil.i('主API出现异常，尝试备用API: ${Config.backupAdApiUrl}');
          final backupResponse = await HttpUtil().getRequest(
            Config.backupAdApiUrl,
            parseData: (data) {
              if (data is! Map<String, dynamic>) {
                LogUtil.e('备用API广告数据格式不正确，期望 JSON 对象，实际为: $data');
                return null;
              }
              
              // 只处理新格式的广告数据
              if (data.containsKey('text_ads') || data.containsKey('video_ads') || 
                  data.containsKey('image_ads')) {
                return AdData.fromJson(data);
              } else {
                LogUtil.e('备用API广告数据格式不符合预期');
                return null;
              }
            },
          );
          
          if (backupResponse != null) {
            _adData = backupResponse;
            LogUtil.i('备用API广告数据加载成功');
            LogUtil.i('文字广告: ${_adData!.textAds.length}个, 视频广告: ${_adData!.videoAds.length}个, 图片广告: ${_adData!.imageAds.length}个');
            
            // 为每种类型安排广告显示
            if (_lastChannelId != null) {
              _scheduleAdsForNewChannel();
            }
            
            _isLoadingAdData = false;
            _adDataLoadedCompleter!.complete(true);
            return true;
          }
        } catch (backupError) {
          LogUtil.e('备用API加载广告数据也失败: $backupError');
        }
      }
      
      _adData = null;
      _isLoadingAdData = false;
      _adDataLoadedCompleter!.complete(false);
      return false;
    }
  }

  // 添加异步版本的视频广告检查，确保数据已加载
  Future<bool> shouldPlayVideoAdAsync() async {
    // 确保广告数据已加载
    if (_adData == null && !_isLoadingAdData) {
      await loadAdData();
    } else if (_adData == null && _isLoadingAdData && _adDataLoadedCompleter != null) {
      await _adDataLoadedCompleter!.future;
    }
    
    return shouldPlayVideoAd();
  }

  // 修改：改进判断是否需要播放视频广告
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

  // 修改：改进播放视频广告方法
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
    Completer<void> adCompletion = Completer<void>();

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
        const Duration(seconds: 36), 
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
      // 更新计数并清理状态
      _adShownCounts[videoAd.id] = (_adShownCounts[videoAd.id] ?? 0) + 1;
      await AdCountManager.saveAdCounts(_adShownCounts);
      
      _isShowingVideoAd = false;
      _currentVideoAd = null;
      
      LogUtil.i('广告播放结束，次数更新: ${_adShownCounts[videoAd.id]} / ${videoAd.displayCount}');
      notifyListeners();
      
      // 视频广告结束后，可以考虑安排其他类型广告
      _schedulePostVideoAds();
    }
  }

  // 新增：视频广告结束后安排其他广告
  void _schedulePostVideoAds() {
    // 使用延迟确保UI已更新
    Timer(Duration(milliseconds: 1000), () {
      // 仅在没有触发过的情况下考虑安排文字广告
      if (!_hasTriggeredTextAdOnCurrentChannel) {
        _scheduleTextAd();
      } 
      // 如果文字广告已触发或没有可用文字广告，考虑图片广告
      else if (!_hasTriggeredImageAdOnCurrentChannel) {
        _scheduleImageAd();
      }
    });
  }

  // 修改：调整视频广告事件监听器，接受Completer参数
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

  // 修改：优化reset方法，更精确控制是否重新调度
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
      _textAdAnimationController?.stop();
      _textAdAnimationController?.reset();
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
      Timer(Duration(milliseconds: MIN_RESCHEDULE_INTERVAL_MS), () {
        // 确保频道ID没有变化
        if (_lastChannelId == currentChannelId) {
          _scheduleAdsForNewChannel();
        }
      });
    }
  }

  // 显式释放所有资源
  void dispose() {
    _cleanupAdController();
    _textAdAnimationController?.dispose();
    _textAdAnimationController = null;
    
    // 取消所有定时器
    _cancelAllAdTimers();
    
    _isShowingTextAd = false;
    _isShowingImageAd = false;
    _isShowingVideoAd = false;
    _currentTextAd = null;
    _currentImageAd = null;
    _currentVideoAd = null;
    _adData = null;
    
    LogUtil.i('广告管理器资源已释放');
  }

  // 获取是否显示文字广告
  bool getShowTextAd() => _isShowingTextAd && _currentTextAd != null && Config.adOn;

  // 获取是否显示图片广告
  bool getShowImageAd() => _isShowingImageAd && _currentImageAd != null && Config.adOn;

  // 获取当前文字广告内容
  String? getTextAdContent() => _currentTextAd?.content;

  // 获取当前文字广告链接
  String? getTextAdLink() => _currentTextAd?.link;

  // 获取当前图片广告
  AdItem? getCurrentImageAd() => _isShowingImageAd ? _currentImageAd : null;

  // 获取视频广告控制器
  BetterPlayerController? getAdController() => _adController;

  // 获取文字广告动画
  Animation<double>? getTextAdAnimation() => _textAdAnimation;
  
  // 构建文字广告 Widget
  Widget buildTextAdWidget({required bool isLandscape}) {
    final content = getTextAdContent()!;
    return Positioned(
      top: isLandscape ? TEXT_AD_TOP_POSITION_LANDSCAPE : TEXT_AD_TOP_POSITION_PORTRAIT,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: getTextAdAnimation()!,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(getTextAdAnimation()!.value, 0),
            child: Text(
              content,
              style: TextStyle(
                color: Colors.white,
                fontSize: TEXT_AD_FONT_SIZE,
                shadows: const [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.0, color: Colors.black)],
              ),
            ),
          );
        },
      ),
    );
  }
  
  // 构建图片广告 Widget
  Widget buildImageAdWidget() {
    final imageAd = getCurrentImageAd()!;
    
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              spreadRadius: 5,
              blurRadius: 15,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                if (imageAd.url != null && imageAd.url!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageAd.url!,
                      fit: BoxFit.contain,
                      height: 300,
                      width: 400,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 300,
                        width: 400,
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
                Positioned(
                  top: 10,
                  right: 10,
                  child: ValueListenableBuilder<int>(
                    valueListenable: imageAdCountdownNotifier,
                    builder: (context, remainingSeconds, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$remainingSeconds秒',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (imageAd.link != null && imageAd.link!.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  handleAdClick(imageAd.link);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('了解更多', style: TextStyle(fontSize: 16)),
              ),
          ],
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
      Uri uri = Uri.parse(link);
      
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
}
