import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';

// 广告数据模型
class AdData {
  final String? textAdContent;
  final bool textAdEnabled;
  final int textAdDisplayCount;
  final String? videoAdUrl;
  final bool videoAdEnabled;
  final int videoAdDisplayCount;

  AdData({
    this.textAdContent,
    required this.textAdEnabled,
    required this.textAdDisplayCount,
    this.videoAdUrl,
    required this.videoAdEnabled,
    required this.videoAdDisplayCount,
  });

  factory AdData.fromJson(Map<String, dynamic> json) {
    return AdData(
      textAdContent: json['text_ad']['content'],
      textAdEnabled: json['text_ad']['enabled'] ?? false,
      textAdDisplayCount: json['text_ad']['display_count'] ?? 0,
      videoAdUrl: json['video_ad']['url'],
      videoAdEnabled: json['video_ad']['enabled'] ?? false,
      videoAdDisplayCount: json['video_ad']['display_count'] ?? 0,
    );
  }
}

// 广告管理类
class AdManager {
  static const String _adApiUrl = 'https://your-api.com/ads'; // API 占位符
  static const String _textAdCountKey = 'text_ad_shown_count';
  static const String _videoAdCountKey = 'video_ad_shown_count';

  AdData? _adData; // 广告数据
  int _textAdShownCount = 0; // 文字广告已显示次数
  int _videoAdShownCount = 0; // 视频广告已显示次数
  bool _showTextAd = false; // 是否显示文字广告
  BetterPlayerController? _adController; // 视频广告控制器

  AdManager() {
    _initCounts();
  }

  // 初始化显示次数
  Future<void> _initCounts() async {
    await SpUtil.getInstance(); // 初始化 SpUtil
    _textAdShownCount = SpUtil.getInt(_textAdCountKey, defValue: 0)!;
    _videoAdShownCount = SpUtil.getInt(_videoAdCountKey, defValue: 0)!;
  }

  // 加载广告数据
  Future<void> loadAdData() async {
    try {
      final response = await HttpUtil.instance.getRequest(
        _adApiUrl,
        parseData: (data) => AdData.fromJson(data),
      );
      if (response != null) {
        _adData = response;
        LogUtil.i('广告数据加载成功: $_adApiUrl');
      } else {
        _adData = null;
        LogUtil.e('广告数据加载失败，返回 null');
      }
    } catch (e) {
      LogUtil.e('加载广告数据失败: $e');
      _adData = null; // API 连接错误时不显示广告
    }
  }

  // 播放视频广告
  Future<void> playVideoAd() async {
    if (_adData == null || !_adData!.videoAdEnabled || _videoAdShownCount >= _adData!.videoAdDisplayCount) {
      return;
    }

    LogUtil.i('开始播放视频广告: ${_adData!.videoAdUrl}');
    try {
      // 使用你的 BetterPlayerConfig 创建数据源和配置
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: _adData!.videoAdUrl!,
        isHls: _isHlsStream(_adData!.videoAdUrl),
      );
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: _isHlsStream(_adData!.videoAdUrl),
        eventListener: _videoAdEventListener,
      );

      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();

      // 等待播放完成，确保资源在播放结束后释放
      await _adController!.videoPlayerController!.stateStream.firstWhere(
        (state) => state.isCompleted == true,
        orElse: () => _adController!.videoPlayerController!.value,
      );

      // 清理资源
      _cleanupAdController();
    } catch (e) {
      LogUtil.e('视频广告播放失败: $e');
      _cleanupAdController();
    }
  }

  // 视频广告事件监听器
  void _videoAdEventListener(BetterPlayerEvent event) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      _videoAdShownCount++;
      SpUtil.putInt(_videoAdCountKey, _videoAdShownCount);
    }
  }

  // 清理视频广告控制器
  void _cleanupAdController() {
    if (_adController != null) {
      _adController!.removeEventsListener(_videoAdEventListener); // 移除监听器
      _adController!.dispose();
      _adController = null;
    }
  }

  // 重置状态并检查是否显示文字广告（切换频道时调用）
  void reset() {
    _cleanupAdController(); // 确保视频广告资源已释放
    _showTextAd = false;

    // 检查文字广告是否需要显示
    if (_adData != null && _adData!.textAdEnabled && _textAdShownCount < _adData!.textAdDisplayCount) {
      _showTextAd = true;
      _textAdShownCount++;
      SpUtil.putInt(_textAdCountKey, _textAdShownCount);
    }
  }

  // 显式释放所有资源
  void dispose() {
    _cleanupAdController(); // 释放视频广告控制器
    _showTextAd = false; // 重置文字广告状态
    _adData = null; // 清空广告数据（可选）
  }

  // 获取是否显示文字广告
  bool getShowTextAd() => _showTextAd && _adData != null && _adData!.textAdEnabled;

  // 获取广告数据
  AdData? getAdData() => _adData;

  // 获取视频广告控制器
  BetterPlayerController? getAdController() => _adController;

  // 判断是否为 HLS 流（简单实现，基于你的播放器逻辑可优化）
  bool _isHlsStream(String? url) {
    return url != null && url.toLowerCase().contains('.m3u8');
  }
}
