import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'dart:async';

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); // 创建 YouTube API 实例，用于获取视频数据
  final http.Client _client = http.Client(); // 创建 HTTP 客户端实例
  bool _isDisposed = false; // 标志位，防止重复释放
  Completer<void>? _completer; // 用于取消异步任务

  StreamUrl(this.url);  // 构造函数，初始化播放 URL

  // 返回处理后的 URL，如果是 YouTube URL，则会解析；如果失败或不是 YouTube URL，返回原始 URL 或 'ERROR'
  Future<String> getStreamUrl() async {
    if (_isDisposed) return 'ERROR';  // 如果已释放资源，直接返回
    _completer = Completer<void>(); // 每次调用都创建一个新的 completer
    try {
      if (!_isYouTubeUrl(url)) {
        return url; // 如果不是 YouTube 链接，直接返回原始 URL
      }
      
      // 如果是 YouTube URL，判断是直播流还是普通视频
      if (url.contains('ytlive')) {
        return await _handleTimeout(_getYouTubeLiveStreamUrl(), '获取 YT 直播流超时');
      } else {
        return await _handleTimeout(_getYouTubeVideoUrl(), '获取 YT 视频流超时');
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

  // 处理超时逻辑的通用方法
  FutureOr<String> _handleTimeout(FutureOr<String?> task, String errorMessage) async {
    return (await task.timeout(Duration(seconds: 8), onTimeout: () {
      LogUtil.e(errorMessage);
      return 'ERROR';
    })) ?? 'ERROR';
  }

  // 处理重试逻辑的通用方法
  Future<T?> _retry<T>(Future<T?> Function() action, int retryCount) async {
    for (int attempt = 0; attempt < retryCount; attempt++) {
      try {
        return await action(); // 执行传入的操作
      } catch (e) {
        if (attempt == retryCount - 1) {
          rethrow; // 最后一次重试失败则抛出异常
        }
      }
    }
    return null;
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

  // 判断 URL 是否为 YouTube 链接
  bool _isYouTubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  // 获取 YouTube 直播流的 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeLiveStreamUrl() async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    String? m3u8Url;
    try {
      m3u8Url = await _retry(() async {
        if (_completer?.isCompleted == true) return null; // 检查任务是否取消
        return await _getYouTubeM3U8Url(url, ['720', '1080', '480', '360', '240']);
      }, 2); // 重试两次
      return m3u8Url;
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取 YT 直播流地址时发生错误', e, stackTrace);
      }
      return null;
    }
  }

  // 获取普通 YouTube 视频的流媒体 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeVideoUrl() async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      return await _retry(() async {
        var video = await _handleTimeout(yt.videos.get(url), '获取视频信息超时');
        if (_isDisposed) return null;  // 如果资源被释放，立即退出
          
        if (video?.isLive ?? false) {
          return await _getYouTubeLiveStreamUrl();
        } else {
          var manifest = await _handleTimeout(yt.videos.streamsClient.getManifest(video!.id), '获取视频流信息超时');
          var streamInfo = _getBestStream(manifest, ['720p', '480p', '360p', '240p', '144p']);
          var streamUrl = streamInfo?.url.toString();
            
          if (streamUrl != null && streamUrl.contains('http')) {
            return streamUrl;
          }
        }
        return null;
      }, 2); // 重试两次
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取视频流地址时发生错误', e, stackTrace);
      }
    }
    return null;  // 最终未成功，返回 null
  }

  // 根据指定的清晰度列表，获取最佳的视频流信息
  StreamInfo? _getBestStream(StreamManifest manifest, List<String> preferredQualities) {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      for (var quality in preferredQualities) {
        var streamInfo = manifest.muxed.firstWhere(
          (element) => element.qualityLabel == quality,
          orElse: () => manifest.muxed.last,
        );
        if (streamInfo != null) {
          return streamInfo;
        }
        if (_isDisposed) return null;  // 资源释放后立即退出
      }
      return null;
    } catch (e, stackTrace) {
      if (!_isDisposed) {
        LogUtil.logError('获取最佳视频流时发生错误', e, stackTrace);
      }
      return null;
    }
  }

  // 获取 YouTube 视频的 m3u8 地址（用于直播流），根据不同的分辨率列表进行选择
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      final response = await _handleTimeout(
        _client.get(
          Uri.parse(youtubeUrl),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ), 
        '获取 m3u8 地址超时'
      );
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
        LogUtil.logError('获取 m3u8 地址时发生错误', e, stackTrace);
      }
    }
    return null;
  }

  // 根据 m3u8 清单中的分辨率，选择最合适的流 URL
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isDisposed) return null;  // 检查是否已经释放资源
    try {
      final response = await _handleTimeout(
        _client.get(Uri.parse(indexM3u8Url)),
        '获取 m3u8 清单超时'
      );
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
        LogUtil.logError('获取质量清单时发生错误', e, stackTrace);
      }
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
}
