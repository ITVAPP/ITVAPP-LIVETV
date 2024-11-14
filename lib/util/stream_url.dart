import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); // 创建 YouTube API 实例，用于获取视频数据
  final http.Client _client = http.Client(); // 创建 HTTP 客户端实例
  bool _isDisposed = false; // 标志位，防止重复释放
  Completer<void>? _completer; // 用于取消异步任务
  final Duration timeoutDuration; // 超时时间变量

  // 构造函数，初始化播放 URL，并允许传入超时时间，默认为 9 秒
  StreamUrl(this.url, {this.timeoutDuration = const Duration(seconds: 9)});

  // 返回处理后的 URL；如果失败或不需要解析，返回原始 URL 或 'ERROR'
  Future<String> getStreamUrl() async {
    if (_isDisposed) return 'ERROR';  // 如果已释放资源，直接返回
    _completer = Completer<void>(); // 每次调用都创建一个新的 completer
    try {
      // 如果不是需要解析的URL，避免后续处理
      if (isLZUrl(url)){
        return 'https://lz.qaiu.top/parser?url=$url'; 
      } 
      
      if (!isYTUrl(url)) {
        return url; // 直接返回原始 URL
      } 
      
      // 选择处理函数
      final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
      
      // 第一次尝试
      try {
        final result = await task().timeout(timeoutDuration);
        // 现在只需要检查是否为 'ERROR'，因为内部方法已经处理了所有失败情况
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
      
      // 等待短暂时间后重试
      await Future.delayed(const Duration(seconds: 1));
      
      // 第二次尝试
      try {
        final result = await task().timeout(timeoutDuration);
        // 同样只需要检查是否为 'ERROR'
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
      return 'ERROR';  // 出现异常时返回 'ERROR'
    } finally {
      if (!_isDisposed) {
        _completer?.complete(); // 确保任务完成
      }
      _completer = null; // 清除 completer
    }
  }

  // 释放资源（关闭 YouTube API 实例和 HTTP 客户端），防止重复调用
  void dispose() {
    if (_isDisposed) return; // 如果已经释放了资源，直接返回
    _isDisposed = true; // 提前设置为已释放，防止重复释放
    
    // 如果有未完成的异步任务，取消它
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源已释放，任务被取消');
    }

    LogUtil.safeExecute(() {
      // 关闭 YouTube API 实例，终止未完成的请求
      try {
        yt.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
      }

      // 关闭 HTTP 客户端，终止未完成的 HTTP 请求
      try {
        _client.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 HTTP 客户端时发生错误', e, stackTrace);
      }
    }, '关闭资源时发生错误');
  }

  // 判断 URL 是否为需要解析处理的链接
  bool isLZUrl(String url) {
    return url.contains('lanzou') ;
  }
  
  // 判断 URL 是否为需要解析处理的链接
  bool isYTUrl(String url) {
    return url.contains('youtube') || url.contains('youtu.be') || url.contains('googlevideo');
  }

// 获取普通 YouTube 视频的流媒体 URL
Future<String> _getYouTubeVideoUrl() async {
  if (_isDisposed) return 'ERROR';
  try {
    var video = await yt.videos.get(url);  
    var manifest = await yt.videos.streams.getManifest(video.id);

    LogUtil.i('''
======= Manifest 流信息 =======
- HLS流数量: ${manifest.hls.length}
- 混合流数量: ${manifest.muxed.length}
===============================''');

  LogUtil.i('manifest 的格式化信息: ${manifest.toString()}');

    // 1. 先尝试在 HLS 流中按质量查找
    if (manifest.hls.isNotEmpty) {
      for (var quality in ['720p', '1080p', '480p', '360p']) {
        var hlsStream = manifest.hls
            .where((s) => s.qualityLabel == quality)
            .firstOrNull;
            
        if (hlsStream != null) {
          var hlsUrl = hlsStream.url.toString();
          if (hlsUrl.isNotEmpty && hlsUrl.contains('http')) {
            LogUtil.i('找到 $quality HLS 流');
            return hlsUrl;
          }
        }
      }
      LogUtil.i('HLS 流中未找到指定质量的流');
    } else {
      LogUtil.i('没有可用的 HLS 流');
    }

    // 2. 如果找不到合适的 HLS 流，尝试混合流
    var streamInfo = _getBestMuxedStream(manifest, ['720p', '1080p', '480p', '360p']);
    if (streamInfo != null) {
      var streamUrl = streamInfo.url.toString();
      if (streamUrl.isNotEmpty && streamUrl.contains('http')) {
        LogUtil.i('''选择的混合流:
- 清晰度: ${streamInfo.qualityLabel}
- 容器格式: ${streamInfo.container.name}
- 比特率: ${streamInfo.bitrate}''');
        return streamUrl;
      }
    }

    // 3. 如果两种方式都没找到，返回 ERROR
    LogUtil.e('未找到任何符合条件的流');
    return 'ERROR';
  } catch (e, stackTrace) {
    LogUtil.logError('获取视频流时发生错误', e, stackTrace);
    return 'ERROR';
  }
}

// 按质量和格式优先级选择最佳混合流
StreamInfo? _getBestMuxedStream(StreamManifest manifest, List<String> preferredQualities) {
  if (manifest.muxed.isEmpty) {
    LogUtil.i('没有可用的混合流');
    return null;
  }

  try {
    // 按质量优先级查找
    for (var quality in preferredQualities) {
      LogUtil.i('查找 $quality 质量的混合流');
      
      // 找出指定质量的所有流
      var qualityStreams = manifest.muxed
          .where((s) => s.qualityLabel == quality)
          .toList();

      if (qualityStreams.isNotEmpty) {
        // 按容器格式优先级：mp4 > webm
        var mp4Stream = qualityStreams
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .firstOrNull;
            
        if (mp4Stream != null) {
          LogUtil.i('找到 MP4 格式的 $quality 流');
          return mp4Stream;
        }

        var webmStream = qualityStreams
            .where((s) => s.container.name.toLowerCase() == 'webm')
            .firstOrNull;
            
        if (webmStream != null) {
          LogUtil.i('找到 WebM 格式的 $quality 流');
          return webmStream;
        }
      }
    }

    LogUtil.i('未找到指定质量的混合流');
    return null;
  } catch (e, stackTrace) {
    LogUtil.logError('选择混合流时发生错误', e, stackTrace);
    return null;
  }
}
  
  // 获取 YouTube 直播流的 URL
  Future<String> _getYouTubeLiveStreamUrl() async {
    if (_isDisposed) return 'ERROR';  // 检查是否已经释放资源
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

  // 获取 YouTube 视频的 m3u8 地址（用于直播流），根据不同的分辨率列表进行选择
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      final response = await _client.get(  // 使用 _client 进行请求
        Uri.parse(youtubeUrl),
        headers: _getRequestHeaders(),
      ).timeout(timeoutDuration);
      if (_isDisposed) return null;  // 资源释放后立即退出

      if (response.statusCode == 200) {
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

  // 根据 m3u8 清单中的分辨率，选择最合适的流 URL
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      final response = await _client.get(Uri.parse(indexM3u8Url))  // 使用 _client 进行请求
          .timeout(timeoutDuration);  // 添加超时处理
      if (_isDisposed) return null;  // 资源释放后立即退出

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        final qualityUrls = <String, String>{};

        for (var i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            final qualityLine = lines[i];
            final quality = _extractQuality(qualityLine);

            if (quality != null && i + 1 < lines.length) {
              final url = lines[i + 1];
              qualityUrls[quality] = url;
            }
          }
          if (_isDisposed) return null;  // 资源释放后立即退出
        }

        for (var preferredQuality in preferredQualities) {
          if (qualityUrls.containsKey(preferredQuality)) {
            return qualityUrls[preferredQuality];
          }
        }

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

  // 从 m3u8 文件的清单行中提取视频质量（分辨率）
  String? _extractQuality(String extInfLine) {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    final regex = RegExp(r'RESOLUTION=\d+x(\d+)');
    final match = regex.firstMatch(extInfLine);

    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  // 提取 User-Agent 和其他 HTTP 请求头
  Map<String, String> _getRequestHeaders() {
    return {
      HttpHeaders.userAgentHeader: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }
}
