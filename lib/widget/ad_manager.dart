import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/config.dart';

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
    // 直接处理根级数据，不考虑嵌套的data字段
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
      } else if (data.containsKey('text_ad')) {
        // 兼容旧格式
        return [AdItem(
          id: 'text_ad',
          content: data['text_ad']['content'],
          enabled: data['text_ad']['enabled'] ?? false,
          displayCount: data['text_ad']['display_count'] ?? 0,
          displayDelaySeconds: data['text_ad']['display_delay_seconds'],
          type: 'text',
        )];
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
      } else if (data.containsKey('video_ad')) {
        // 兼容旧格式
        return [AdItem(
          id: 'video_ad',
          url: data['video_ad']['url'],
          enabled: data['video_ad']['enabled'] ?? false,
          displayCount: data['video_ad']['display_count'] ?? 0,
          type: 'video',
        )];
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
      } else if (data.containsKey('image_ad')) {
        // 兼容简单的单个图片广告格式
        return [AdItem(
          id: 'image_ad',
          url: data['image_ad']['url'],
          enabled: data['image_ad']['enabled'] ?? false,
          displayCount: data['image_ad']['display_count'] ?? 0,
          displayDelaySeconds: data['image_ad']['display_delay_seconds'],
          durationSeconds: data['image_ad']['duration_seconds'] ?? 8,
          type: 'image',
        )];
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
  AdData? _adData; // 广告数据
  Map<String, int> _adShownCounts = {}; // 各广告已显示次数
  Map<String, Timer?> _adTimers = {}; // 各广告延迟定时器
  
  // 当前显示状态
  bool _isShowingTextAd = false;
  bool _isShowingVideoAd = false;
  bool _isShowingImageAd = false;
  
  // 当前显示的广告
  AdItem? _currentTextAd;
  AdItem? _currentImageAd;
  AdItem? _currentVideoAd;
  
  String? _lastChannelId; // 记录上次频道ID，用于检测频道切换
  bool _hasTriggeredAdOnCurrentChannel = false; // 当前频道是否已触发广告
  
  // 视频广告控制器
  BetterPlayerController? _adController;
  
  // 文字广告动画控制
  AnimationController? _textAdAnimationController;
  Animation<double>? _textAdAnimation;

  AdManager() {
    _init();
  }

  // 初始化
  Future<void> _init() async {
    // 加载广告计数
    _adShownCounts = await AdCountManager.loadAdCounts();
  }
  
  // 处理频道切换事件
  void onChannelChanged(String channelId) {
    if (_lastChannelId != channelId) {
      _lastChannelId = channelId;
      _hasTriggeredAdOnCurrentChannel = false;
      LogUtil.i('检测到频道切换: $channelId');
    }
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
  
  // 初始化文字广告滚动动画（需在 Widget 中调用）
  void initTextAdAnimation(TickerProvider vsync, double screenWidth) {
    if (_textAdAnimationController == null && _currentTextAd?.content != null) {
      _textAdAnimationController = AnimationController(
        vsync: vsync,
        duration: const Duration(seconds: 10), // 滚动周期 10 秒，可调整
      )..repeat(); // 无限循环

      // 计算文字滚动的起始和结束位置
      final textWidth = _calculateTextWidth(_currentTextAd!.content!);
      _textAdAnimation = Tween<double>(
        begin: screenWidth, // 从屏幕右侧开始
        end: -textWidth,   // 滚动到文字完全移出左侧
      ).animate(_textAdAnimationController!);
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
        style: const TextStyle(fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.width;
  }
  
  // 安排显示文字广告
  void _scheduleTextAd() {
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不安排文字广告');
      return;
    }
    
    if (_isShowingTextAd || _isShowingVideoAd || _adData == null || 
        _hasTriggeredAdOnCurrentChannel) {
      LogUtil.i('不安排文字广告: already showing=${_isShowingTextAd}, videoShowing=${_isShowingVideoAd}, hasData=${_adData != null}, triggered=${_hasTriggeredAdOnCurrentChannel}');
      return;
    }
      
    final nextAd = _selectNextAd(_adData!.textAds);
    if (nextAd == null) {
      LogUtil.i('没有可显示的文字广告');
      return;
    }
    
    // 使用广告指定的延迟时间，默认5分钟
    final delaySeconds = nextAd.displayDelaySeconds ?? 300;
    LogUtil.i('安排文字广告 ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    _adTimers[nextAd.id]?.cancel();
    _adTimers[nextAd.id] = Timer(Duration(seconds: delaySeconds), () {
      // 再次检查广告开关状态
      if (!Config.adOn) {
        LogUtil.i('广告功能已关闭，取消显示文字广告');
        return;
      }
      
      if (_isShowingVideoAd || _isShowingImageAd) {
        LogUtil.i('因其他广告正在显示而取消文字广告');
        return; // 避免与其他广告冲突
      }
      
      _currentTextAd = nextAd;
      _isShowingTextAd = true;
      _adShownCounts[nextAd.id] = (_adShownCounts[nextAd.id] ?? 0) + 1;
      AdCountManager.saveAdCounts(_adShownCounts);
      _hasTriggeredAdOnCurrentChannel = true;
      
      LogUtil.i('显示文字广告 ${nextAd.id}, 当前次数: ${_adShownCounts[nextAd.id]} / ${nextAd.displayCount}');
      notifyListeners();
    });
  }
  
  // 安排显示图片广告
  void _scheduleImageAd() {
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不安排图片广告');
      return;
    }
    
    if (_isShowingImageAd || _isShowingVideoAd || _adData == null || 
        _hasTriggeredAdOnCurrentChannel) {
      LogUtil.i('不安排图片广告: already showing=${_isShowingImageAd}, videoShowing=${_isShowingVideoAd}, hasData=${_adData != null}, triggered=${_hasTriggeredAdOnCurrentChannel}');
      return;
    }
      
    final nextAd = _selectNextAd(_adData!.imageAds);
    if (nextAd == null) {
      LogUtil.i('没有可显示的图片广告');
      return;
    }
    
    // 使用广告指定的延迟时间，默认2分钟
    final delaySeconds = nextAd.displayDelaySeconds ?? 120;
    LogUtil.i('安排图片广告 ${nextAd.id} 延迟 $delaySeconds 秒后显示');
    
    _adTimers[nextAd.id]?.cancel();
    _adTimers[nextAd.id] = Timer(Duration(seconds: delaySeconds), () {
      // 再次检查广告开关状态
      if (!Config.adOn) {
        LogUtil.i('广告功能已关闭，取消显示图片广告');
        return;
      }
      
      if (_isShowingVideoAd || _isShowingTextAd) {
        LogUtil.i('因其他广告正在显示而取消图片广告');
        return; // 避免与其他广告冲突
      }
      
      _currentImageAd = nextAd;
      _isShowingImageAd = true;
      _adShownCounts[nextAd.id] = (_adShownCounts[nextAd.id] ?? 0) + 1;
      AdCountManager.saveAdCounts(_adShownCounts);
      _hasTriggeredAdOnCurrentChannel = true;
      
      LogUtil.i('显示图片广告 ${nextAd.id}, 当前次数: ${_adShownCounts[nextAd.id]} / ${nextAd.displayCount}');
      notifyListeners();
      
      // 设置自动关闭
      final durationSeconds = nextAd.durationSeconds ?? 8;
      Timer(Duration(seconds: durationSeconds), () {
        if (_currentImageAd?.id == nextAd.id) {
          _isShowingImageAd = false;
          _currentImageAd = null;
          LogUtil.i('图片广告 ${nextAd.id} 自动关闭');
          notifyListeners();
        }
      });
    });
  }
  
  // 加载广告数据
  Future<void> loadAdData() async {
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不加载广告数据');
      return;
    }
    
    try {
      final response = await HttpUtil().getRequest(
        Config.adApiUrl,
        parseData: (data) {
          if (data is! Map<String, dynamic>) {
            LogUtil.e('广告数据格式不正确，期望 JSON 对象，实际为: $data');
            return null;
          }
          
          // 直接解析广告数据，不考虑嵌套结构
          if (data.containsKey('text_ad') || data.containsKey('video_ad') ||
              data.containsKey('text_ads') || data.containsKey('video_ads') || 
              data.containsKey('image_ads') || data.containsKey('image_ad')) {
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
        _scheduleTextAd();
        _scheduleImageAd();
        
      } else {
        _adData = null;
        LogUtil.e('广告数据加载失败，返回 null，可能服务器返回空响应或数据格式错误');
      }
    } catch (e) {
      LogUtil.e('加载广告数据失败: $e');
      _adData = null;
    }
  }

  // 判断是否需要播放视频广告
  bool shouldPlayVideoAd() {
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不需要播放视频广告');
      return false;
    }
    
    if (_adData == null || _hasTriggeredAdOnCurrentChannel) {
      LogUtil.i('不需要播放视频广告: hasData=${_adData != null}, triggered=${_hasTriggeredAdOnCurrentChannel}');
      return false;
    }
    
    final nextAd = _selectNextAd(_adData!.videoAds);
    final shouldPlay = nextAd != null;
    
    if (shouldPlay) {
      _currentVideoAd = nextAd;
      LogUtil.i('需要播放视频广告: ${nextAd!.id}');
    } else {
      LogUtil.i('没有可播放的视频广告');
    }
    
    return shouldPlay;
  }

  // 播放视频广告并等待其完成
  Future<void> playVideoAd() async {
    // 检查广告开关
    if (!Config.adOn) {
      LogUtil.i('广告功能已关闭，不播放视频广告');
      return;
    }
    
    if (!shouldPlayVideoAd() || _currentVideoAd == null) {
      LogUtil.i('无需播放视频广告：无数据、未启用或已达上限');
      return;
    }
    
    final videoAd = _currentVideoAd!;
    LogUtil.i('开始播放视频广告: ${videoAd.url}');
    _isShowingVideoAd = true;
    _hasTriggeredAdOnCurrentChannel = true;
    notifyListeners();
    
    Completer<void> adCompletion = Completer<void>(); // 创建 Completer 用于等待广告完成

    try {
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: videoAd.url!,
        isHls: _isHlsStream(videoAd.url),
      );
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: _isHlsStream(videoAd.url),
        eventListener: (event) => _videoAdEventListener(event, adCompletion), // 传递 Completer
      );

      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();

      // 等待广告播放完成或超时
      await adCompletion.future.timeout(const Duration(seconds: 36), onTimeout: () {
        LogUtil.i('广告播放超时，默认结束');
        _cleanupAdController();
        if (!adCompletion.isCompleted) {
          adCompletion.complete();
        }
      });
    } catch (e) {
      LogUtil.e('视频广告播放失败: $e');
      _cleanupAdController();
      if (!adCompletion.isCompleted) {
        adCompletion.completeError(e); // 如果失败，完成错误
      }
      rethrow; // 抛出异常给调用者处理
    } finally {
      _adShownCounts[videoAd.id] = (_adShownCounts[videoAd.id] ?? 0) + 1;
      AdCountManager.saveAdCounts(_adShownCounts);
      _isShowingVideoAd = false;
      _currentVideoAd = null;
      LogUtil.i('广告播放次数更新: ${_adShownCounts[videoAd.id]} / ${videoAd.displayCount}');
    }
  }

  // 调整 _videoAdEventListener，接受 Completer 参数
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

  // 重置状态
  void reset() {
    _cleanupAdController();
    
    // 取消所有定时器
    for (var timer in _adTimers.values) {
      timer?.cancel();
    }
    _adTimers.clear();
    
    // 清理显示状态，但保留计数
    _isShowingTextAd = false;
    _isShowingImageAd = false;
    _isShowingVideoAd = false;
    _currentTextAd = null;
    _currentImageAd = null;
    _currentVideoAd = null;
    
    LogUtil.i('广告管理器状态已重置');
  }

  // 显式释放所有资源
  void dispose() {
    _cleanupAdController();
    _textAdAnimationController?.dispose();
    _textAdAnimationController = null;
    
    // 取消所有定时器
    for (var timer in _adTimers.values) {
      timer?.cancel();
    }
    _adTimers.clear();
    
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
