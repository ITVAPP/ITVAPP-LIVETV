import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); // 创建 YouTube API 实例，用于获取视频数据
  final http.Client _client = http.Client(); // 创建 HTTP 客户端实例，用于发送网络请求
  bool _isDisposed = false; // 标志位，用于防止资源重复释放和避免已释放资源的操作
  Completer<void>? _completer; // 用于控制和取消异步任务的完成器
  final Duration timeoutDuration; // 定义请求超时时间，可在构造时指定

  // 构造函数：初始化必要的 URL 和可选的超时时间（默认 9 秒）
  StreamUrl(this.url, {this.timeoutDuration = const Duration(seconds: 9)});

  // 获取媒体流 URL：根据不同类型的 URL 进行相应处理并返回可用的流地址
  Future<String> getStreamUrl() async {
    if (_isDisposed) return 'ERROR';  // 如果资源已释放，返回错误状态
    _completer = Completer<void>(); // 创建新的完成器用于控制当前请求
    try {
      // 处理蓝奏云链接：直接返回解析接口地址
      if (isLZUrl(url)){
        return 'https://lz.qaiu.top/parser?url=$url'; 
      } 
      
      // 非 YouTube 链接：直接返回原始 URL
      if (!isYTUrl(url)) {
        return url;
      } 
      
      // 根据 URL 类型选择相应的处理函数：直播流或普通视频
      final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
      
      // 第一次尝试获取流地址
      try {
        final result = await task().timeout(timeoutDuration);
        if (result != 'ERROR') {
          LogUtil.i('首次获取视频流成功');
          return result;
        }
        LogUtil.e('首次获取视频流失败，准备重试');
      } catch (e) {
        if (e is TimeoutException) {
          LogUtil.e('首次获取视频流超时，准备重试');
        } else {
          LogUtil.e('首次获取视频流失败: ${e.toString()}，准备重试');
        }
      }
      
      // 首次失败后等待 1 秒进行重试
      await Future.delayed(const Duration(seconds: 1));
      
      // 第二次尝试获取流地址
      try {
        final result = await task().timeout(timeoutDuration);
        if (result != 'ERROR') {
          LogUtil.i('重试获取视频流成功');
          return result;
        }
        LogUtil.e('重试获取视频流失败');
        return 'ERROR';
      } catch (retryError) {
        if (retryError is TimeoutException) {
          LogUtil.e('重试获取视频流超时');
        } else {
          LogUtil.e('重试获取视频流失败: ${retryError.toString()}');
        }
        return 'ERROR';
      }
      
    } catch (e, stackTrace) {
      LogUtil.logError('获取视频流地址时发生错误', e, stackTrace);
      return 'ERROR';  // 发生任何未处理的异常时返回错误状态
    } finally {
      if (!_isDisposed) {
        _completer?.complete(); // 确保异步任务正常完成
      }
      _completer = null; // 清理完成器引用
    }
  }

  // 释放所有资源：包括 YouTube API 实例和 HTTP 客户端
  void dispose() {
    if (_isDisposed) return; // 防止重复释放
    _isDisposed = true; // 标记为已释放状态
    
    // 取消未完成的异步任务
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源已释放，任务被取消');
    }

    LogUtil.safeExecute(() {
      // 释放 YouTube API 实例
      try {
        yt.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
      }

      // 释放 HTTP 客户端实例
      try {
        _client.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 HTTP 客户端时发生错误', e, stackTrace);
      }
    }, '关闭资源时发生错误');
  }

  // 判断是否为蓝奏云分享链接
  bool isLZUrl(String url) {
    return url.contains('lanzou');
  }
  
  // 判断是否为 YouTube 相关链接
  bool isYTUrl(String url) {
    return url.contains('youtube') || url.contains('youtu.be') || url.contains('googlevideo');
  }

// 验证 URL 的基本有效性
bool _isValidUrl(String url) {
  return url.isNotEmpty && url.contains('http');
}

// 获取视频流 URL
Future<String> _getYouTubeVideoUrl() async {
  if (_isDisposed) return 'ERROR';
  
  try {
    var video = await yt.videos.get(url);
    
    // 使用 safari 客户端获取高质量 HLS 流
    var manifest = await yt.videos.streams.getManifest(
      video.id,
      ytClients: [YoutubeApiClient.safari],
    );
    LogUtil.i('格式化manifest的信息调试用: ${manifest.toString()}');
    LogUtil.i('''
======= 获取统计 =======
- HLS流数量: ${manifest.hls.length}
- 混合流数量: ${manifest.muxed.length}
===============================''');
    
    // 记录所有可用的 HLS 混合流信息
    if (manifest.hls.isNotEmpty) {
      LogUtil.i('可用的 HLS 混合流:');
      var hlsStreams = manifest.hls.whereType<HlsMuxedStreamInfo>();
      
      // 从qualityLabel提取精确分辨率
      int getExactResolution(String label) {
        final match = RegExp(r'^(\d+)p').firstMatch(label);
        return match != null ? int.parse(match.group(1)!) : 0;
      }

      hlsStreams.forEach((s) => LogUtil.i('''
- 分辨率: ${getExactResolution(s.qualityLabel)}p
- qualityLabel: ${s.qualityLabel}
- videoQuality: ${s.videoQuality}
- 音频编码: ${s.audioCodec}
- 视频编码: ${s.videoCodec}
'''));

      // 按照优先级尝试获取指定分辨率的 HLS 流
      for (var targetRes in [720, 1080, 480]) {
        var hlsStream = hlsStreams
            .where((s) => getExactResolution(s.qualityLabel) == targetRes && 
                         _isValidUrl(s.url.toString()))
            .firstOrNull;
            
        if (hlsStream != null) {
          LogUtil.i('找到精确匹配 ${targetRes}p HLS混合流');
          return hlsStream.url.toString();
        }
      }

      // 如果没找到指定分辨率,尝试获取最接近的分辨率
      if (hlsStreams.isNotEmpty) {
        var closest = hlsStreams
            .where((s) => _isValidUrl(s.url.toString()))
            .reduce((a, b) {
              final aDiff = (getExactResolution(a.qualityLabel) - 720).abs(); // 以720p为基准
              final bDiff = (getExactResolution(b.qualityLabel) - 720).abs();
              return aDiff < bDiff ? a : b;
            });
            
        final resolution = getExactResolution(closest.qualityLabel);
        LogUtil.i('使用最接近的HLS流: ${resolution}p');
        return closest.url.toString();
      }
      
      LogUtil.i('HLS混合流中未找到合适的流');
    } else {
      LogUtil.i('没有可用的 HLS 流');
    }

    // 如果没有合适的 HLS 流，回退到普通混合流
    var streamInfo = await _getBestMuxedStream(manifest);
    if (streamInfo != null) {
      var streamUrl = streamInfo.url.toString();
      if (_isValidUrl(streamUrl)) {
        return streamUrl;
      }
    }

    LogUtil.e('未找到任何符合条件的流');
    return 'ERROR';
    
  } catch (e, stackTrace) {
    LogUtil.logError('获取视频流时发生错误', e, stackTrace);
    return 'ERROR';
  }
}

// 获取最佳的普通混合流
StreamInfo? _getBestMuxedStream(StreamManifest manifest) {
  if (manifest.muxed.isEmpty) {
    LogUtil.i('没有可用的混合流');
    return null;
  }

  try {
    LogUtil.i('查找最佳质量的普通混合流');
    
    // 按分辨率降序排列并过滤有效URL
    var sortedStreams = manifest.muxed
        .where((s) => _isValidUrl(s.url.toString()))
        .toList()
      ..sort((a, b) => b.videoQuality.compareTo(a.videoQuality));

    // 优先返回最高质量的 MP4 格式
    var mp4Stream = sortedStreams
        .where((s) => s.container.name.toLowerCase() == 'mp4')
        .firstOrNull;
        
    if (mp4Stream != null) {
      LogUtil.i('找到最佳 MP4 格式混合流: ${mp4Stream.videoQuality}');
      return mp4Stream;
    }

    // 如果没有 MP4，返回最高质量的其他格式
    if (sortedStreams.isNotEmpty) {
      LogUtil.i('找到最佳其他格式混合流: ${sortedStreams.first.videoQuality}');
      return sortedStreams.first;
    }

    LogUtil.i('未找到可用的普通混合流');
    return null;
    
  } catch (e, stackTrace) {
    LogUtil.logError('选择混合流时发生错误', e, stackTrace);
    return null;
  }
}
  
  // 获取 YouTube 直播流的 URL
  Future<String> _getYouTubeLiveStreamUrl() async {
    if (_isDisposed) return 'ERROR';
    try {
      final m3u8Url = await _getYouTubeM3U8Url(url, ['720', '1080', '480', '360']);
      if (m3u8Url != null) {
        LogUtil.i('获取到 YT 直播流地址: $m3u8Url');
        return m3u8Url;
      }
      LogUtil.e('未能获取到有效的直播流地址');
      return 'ERROR';
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取 YT 直播流地址时发生错误', e, stackTrace);
      }
      return 'ERROR';
    }
  }

  // 获取 YouTube 直播的 m3u8 清单地址
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isDisposed) return null;
    try {
      // 发送请求获取页面内容
      final response = await _client.get(
        Uri.parse(youtubeUrl),
        headers: _getRequestHeaders(),
      ).timeout(timeoutDuration);
      if (_isDisposed) return null;

      if (response.statusCode == 200) {
        // 使用正则表达式提取 m3u8 地址
        final regex = RegExp(r'"hlsManifestUrl":"(https://[^"]+\.m3u8)"');
        final match = regex.firstMatch(response.body);

        if (match != null) {
          final indexM3u8Url = match.group(1);
          if (indexM3u8Url != null) {
            return await _getQualityM3U8Url(indexM3u8Url, preferredQualities);
          }
        }
      }
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取 M3U8 URL 时发生错误', e, stackTrace);
      }
      return null;
    }
    return null;
  }

  // 从 m3u8 清单中选择指定质量的流地址
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isDisposed) return null;
    try {
      // 获取 m3u8 清单内容
      final response = await _client.get(Uri.parse(indexM3u8Url))
          .timeout(timeoutDuration);
      if (_isDisposed) return null;

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        final qualityUrls = <String, String>{};

        // 解析清单内容，提取不同质量的流地址
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            final qualityLine = lines[i];
            final quality = _extractQuality(qualityLine);

            if (quality != null && i + 1 < lines.length) {
              final url = lines[i + 1];
              qualityUrls[quality] = url;
            }
          }
          if (_isDisposed) return null;
        }

        // 按照优先级查找指定质量的流
        for (var preferredQuality in preferredQualities) {
          if (qualityUrls.containsKey(preferredQuality)) {
            return qualityUrls[preferredQuality];
          }
        }

        // 如果没有找到指定质量，返回第一个可用的流
        if (qualityUrls.isNotEmpty) {
          return qualityUrls.values.first;
        }
      }
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取质量 M3U8 URL 时发生错误', e, stackTrace);
      }
      return null;
    }
    return null;
  }

  // 从 m3u8 清单行提取视频质量信息
  String? _extractQuality(String extInfLine) {
    if (_isDisposed) return null;
    // 使用正则表达式匹配分辨率信息
    final regex = RegExp(r'RESOLUTION=\d+x(\d+)');
    final match = regex.firstMatch(extInfLine);

    if (match != null) {
      return match.group(1);
    }
    return null;
  }

// 获取 HTTP 请求需要的头信息，设置 User-Agent 来模拟浏览器访问
  Map<String, String> _getRequestHeaders() {
    return {
      HttpHeaders.userAgentHeader: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }
}
