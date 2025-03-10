import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/config.dart';

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
class AdManager with ChangeNotifier {
  AdData? _adData; // 广告数据
  int _textAdShownCount = 0; // 文字广告已显示次数
  int _videoAdShownCount = 0; // 视频广告已显示次数
  bool _showTextAd = false; // 是否显示文字广告
  BetterPlayerController? _adController; // 视频广告控制器
  AnimationController? _textAdAnimationController; // 文字广告滚动控制器
  Animation<double>? _textAdAnimation; // 文字广告滚动动画

  AdManager() {
    _initCounts();
  }

  // 初始化显示次数
  Future<void> _initCounts() async {
    await SpUtil.getInstance(); // 初始化 SpUtil
    _textAdShownCount = SpUtil.getInt(Config.textAdCountKey, defValue: 0)!;
    _videoAdShownCount = SpUtil.getInt(Config.videoAdCountKey, defValue: 0)!;
  }

  // 初始化文字广告滚动动画（需在 Widget 中调用）
  void initTextAdAnimation(TickerProvider vsync, double screenWidth) {
    if (_textAdAnimationController == null && _adData?.textAdContent != null) { // 仅当有广告内容时初始化
      _textAdAnimationController = AnimationController(
        vsync: vsync,
        duration: const Duration(seconds: 10), // 滚动周期 10 秒，可调整
      )..repeat(); // 无限循环

      // 计算文字滚动的起始和结束位置
      final textWidth = _calculateTextWidth(_adData!.textAdContent!); // 使用实际广告内容
      _textAdAnimation = Tween<double>(
        begin: screenWidth, // 从屏幕右侧开始
        end: -textWidth,   // 滚动到文字完全移出左侧
      ).animate(_textAdAnimationController!);
    }
  }

  // 更新文字广告动画（用于屏幕宽度变化时）
  void updateTextAdAnimation(double screenWidth) {
    if (_textAdAnimationController != null && _adData?.textAdContent != null) {
      final textWidth = _calculateTextWidth(_adData!.textAdContent!);
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

  // 加载广告数据
  // 示例 API 返回格式：
  // {
  //   "text_ad": {
  //     "content": "欢迎体验我们的产品！",
  //     "enabled": true,
  //     "display_count": 3
  //   },
  //   "video_ad": {
  //     "url": "https://example.com/ad_video.m3u8",
  //     "enabled": true,
  //     "display_count": 1
  //   }
  // }
  Future<void> loadAdData() async {
    try {
      final response = await HttpUtil().getRequest(
        Config.adApiUrl,
        parseData: (data) {
          if (data is! Map<String, dynamic>) {
            LogUtil.e('广告数据格式不正确，期望 JSON 对象，实际为: $data');
            return null;
          }
          if (!data.containsKey('text_ad') || !data.containsKey('video_ad')) {
            LogUtil.e('广告数据缺少必要字段: text_ad 或 video_ad');
            return null;
          }
          return AdData.fromJson(data);
        },
      );
      if (response != null) {
        _adData = response;
        LogUtil.i('广告数据加载成功: ${Config.adApiUrl}');
      } else {
        _adData = null;
        LogUtil.e('广告数据加载失败，返回 null，可能服务器返回空响应或数据格式错误');
      }
    } catch (e) {
      LogUtil.e('加载广告数据失败: $e');
      _adData = null;
    }
  }

  // 修改处：播放视频广告并等待其完成
  Future<void> playVideoAd() async {
    if (_adData == null || !_adData!.videoAdEnabled || _videoAdShownCount >= _adData!.videoAdDisplayCount) {
      LogUtil.i('广告未启用或已达上限，无需播放');
      return;
    }

    LogUtil.i('开始播放视频广告: ${_adData!.videoAdUrl}');
    Completer<void> adCompletion = Completer<void>(); // 创建 Completer 用于等待广告完成

    try {
      final adDataSource = BetterPlayerConfig.createDataSource(
        url: _adData!.videoAdUrl!,
        isHls: _isHlsStream(_adData!.videoAdUrl),
      );
      final adConfig = BetterPlayerConfig.createPlayerConfig(
        isHls: _isHlsStream(_adData!.videoAdUrl),
        eventListener: (event) => _videoAdEventListener(event, adCompletion), // 传递 Completer
      );

      _adController = BetterPlayerController(adConfig);
      await _adController!.setupDataSource(adDataSource);
      await _adController!.play();

      // 等待广告播放完成或超时
      await adCompletion.future.timeout(const Duration(seconds: 36), onTimeout: () {
        LogUtil.w('广告播放超时，默认结束');
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
    }
  }

  // 修改处：调整 _videoAdEventListener，接受 Completer 参数
  void _videoAdEventListener(BetterPlayerEvent event, Completer<void> completer) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      LogUtil.i('视频广告播放完成');
      _cleanupAdController();
      _videoAdShownCount++;
      SpUtil.putInt(Config.videoAdCountKey, _videoAdShownCount);
      if (!completer.isCompleted) {
        completer.complete(); // 完成 Future，表示广告播放结束
      }
    }
  }

  // 清理视频广告控制器
  void _cleanupAdController() {
    if (_adController != null) {
      _adController!.dispose(); // 修改处：移除 removeEventsListener，因为 dispose 已清理事件
      _adController = null;
    }
  }

  // 重置状态并检查是否显示文字广告
  void reset() {
    _cleanupAdController();
    _showTextAd = false;

    // 检查文字广告是否需要显示
    if (_adData != null && _adData!.textAdEnabled && _textAdShownCount < _adData!.textAdDisplayCount) {
      _showTextAd = true;
      _textAdShownCount++;
      SpUtil.putInt(Config.textAdCountKey, _textAdShownCount);
      notifyListeners(); // 通知 UI 更新
    }
  }

  // 显式释放所有资源
  void dispose() {
    _cleanupAdController();
    _textAdAnimationController?.dispose();
    _textAdAnimationController = null;
    _showTextAd = false;
    _adData = null;
  }

  // 获取是否显示文字广告
  bool getShowTextAd() => _showTextAd && _adData != null && _adData!.textAdEnabled;

  // 获取广告数据
  AdData? getAdData() => _adData;

  // 获取视频广告控制器
  BetterPlayerController? getAdController() => _adController;

  // 获取文字广告动画
  Animation<double>? getTextAdAnimation() => _textAdAnimation;

  // 判断是否为 HLS 流
  bool _isHlsStream(String? url) {
    return url != null && url.toLowerCase().contains('.m3u8');
  }
}
