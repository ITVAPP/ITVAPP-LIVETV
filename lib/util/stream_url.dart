import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); // 创建 YouTube API 实例，用于获取视频数据
  bool _isDisposed = false; // 标志位，防止重复释放

  StreamUrl(this.url);  // 构造函数，初始化播放 URL

  // 返回处理后的 URL，如果是 YouTube URL，则会解析；如果失败或不是 YouTube URL，返回原始 URL 或 'ERROR'
  Future<String> getStreamUrl() async {
    try {
      LogUtil.i('尝试获取视频流地址: $url');
      
      if (_isYouTubeUrl(url)) {
        if (url.contains('ytlive')) {
          LogUtil.i('检测到 YouTube 直播流');
          return await _getYouTubeLiveStreamUrl() ?? 'ERROR';  // 处理 YouTube 直播视频
        } else {
          LogUtil.i('检测到普通 YouTube 视频');
          return await _getYouTubeVideoUrl() ?? 'ERROR';  // 处理普通 YouTube 视频
        }
      }
      return url; // 如果不是 YouTube 链接，直接返回原始 URL
    } catch (e, stackTrace) {
      LogUtil.logError('获取视频流地址时发生错误', e, stackTrace);
      return 'ERROR';  // 出现异常时返回 'ERROR'
    }
  }

  // 释放资源（关闭 YouTube API 实例），防止重复调用
  void dispose() {
    if (_isDisposed) return; // 如果已经释放了资源，直接返回
    LogUtil.safeExecute(() {
      yt.close();
      _isDisposed = true; // 设置为已释放
      LogUtil.i('YouTubeExplode 实例已关闭');
    }, '关闭 YouTubeExplode 实例时发生错误');
  }

  // 判断 URL 是否为 YouTube 链接（检测是否包含 'youtube.com' 或 'youtu.be'）
  bool _isYouTubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  // 获取 YouTube 直播流的 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeLiveStreamUrl() async {
    String? m3u8Url;
    try {
      for (int i = 0; i < 2; i++) {
        m3u8Url = await _getYouTubeM3U8Url(url, ['720', '1080', '480', '360', '240']);
        if (m3u8Url != null) break;  // 如果获取成功，跳出循环
      }
      LogUtil.i('获取到 YouTube 直播流地址: $m3u8Url');
      return m3u8Url;
    } catch (e, stackTrace) {
      LogUtil.logError('获取 YouTube 直播流地址时发生错误', e, stackTrace);
      return null;
    }
  }

  // 获取普通 YouTube 视频的流媒体 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeVideoUrl() async {
    try {
      var video = await yt.videos.get(url);  // 获取视频详细信息
      LogUtil.d('获取视频数据成功: ${video.id}');
      
      if (video.isLive) {
        return await _getYouTubeLiveStreamUrl();
      } else {
        var manifest = await yt.videos.streamsClient.getManifest(video.id);
        var streamInfo = _getBestStream(manifest, ['720p', '480p', '360p', '240p', '144p']);
        return streamInfo?.url.toString();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取 YouTube 视频流地址时发生错误', e, stackTrace);
      return null;
    }
  }

  // 根据指定的清晰度列表，获取最佳的视频流信息
  StreamInfo? _getBestStream(StreamManifest manifest, List<String> preferredQualities) {
    try {
      for (var quality in preferredQualities) {
        var streamInfo = manifest.muxed.firstWhere(
          (element) => element.qualityLabel == quality,
          orElse: () => manifest.muxed.last,
        );
        if (streamInfo != null) {
          LogUtil.i('找到最佳质量的视频流: $quality');
          return streamInfo;
        }
      }
      LogUtil.e('没有找到匹配的质量，使用默认流');
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取最佳视频流时发生错误', e, stackTrace);
      return null;
    }
  }

  // 获取 YouTube 视频的 m3u8 地址（用于直播流），根据不同的分辨率列表进行选择
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    try {
      final response = await http.get(
        Uri.parse(youtubeUrl),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(Duration(seconds: 10));

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
      LogUtil.logError('获取 YouTube m3u8 地址时发生错误', e, stackTrace);
    }
    return null;
  }

  // 根据 m3u8 清单中的分辨率，选择最合适的流 URL
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    try {
      final response = await http.get(Uri.parse(indexM3u8Url));

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
        }

        for (var preferredQuality in preferredQualities) {
          if (qualityUrls.containsKey(preferredQuality)) {
            LogUtil.d('找到匹配的分辨率: $preferredQuality');
            return qualityUrls[preferredQuality];
          }
        }

        if (qualityUrls.isNotEmpty) {
          LogUtil.e('没有找到匹配的分辨率，使用默认流');
          return qualityUrls.values.first;
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取最合适的 m3u8 地址时发生错误', e, stackTrace);
    }
    return null;
  }

  // 从 m3u8 文件的清单行中提取视频质量（分辨率）
  String? _extractQuality(String extInfLine) {
    final regex = RegExp(r'RESOLUTION=\d+x(\d+)');
    final match = regex.firstMatch(extInfLine);

    if (match != null) {
      LogUtil.d('提取到的分辨率: ${match.group(1)}');
      return match.group(1);
    }
    LogUtil.e('未能提取到分辨率: $extInfLine');
    return null;
  }
}
