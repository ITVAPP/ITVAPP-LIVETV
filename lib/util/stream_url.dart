import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); // 创建 YouTube API 实例，用于获取视频数据

  StreamUrl(this.url);  // 构造函数，初始化播放 URL

  // 返回处理后的 URL，如果是 YouTube URL，则会解析；如果失败或不是 YouTube URL，返回原始 URL 或 'ERROR'
  Future<String> getStreamUrl() async {
    try {
      // 判断是否是 YouTube 链接
      if (_isYouTubeUrl(url)) {
        // 如果是 YouTube 直播，获取直播流 URL
        if (url.contains('ytlive')) {
          return await _getYouTubeLiveStreamUrl() ?? 'ERROR';  // 处理 YouTube 直播视频
        } else {
          return await _getYouTubeVideoUrl() ?? 'ERROR';  // 处理普通 YouTube 视频
        }
      }
      return url; // 如果不是 YouTube 链接，直接返回原始 URL
    } catch (e) {
      return 'ERROR';  // 出现异常时返回 'ERROR'
    }
  }

  // 释放资源（关闭 YouTube API 实例）
  void dispose() {
    yt.close();
  }

  // 判断 URL 是否为 YouTube 链接（检测是否包含 'youtube.com' 或 'youtu.be'）
  bool _isYouTubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  // 获取 YouTube 直播流的 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeLiveStreamUrl() async {
    String? m3u8Url;
    // 尝试最多两次获取 m3u8 地址，按不同的分辨率优先顺序
    for (int i = 0; i < 2; i++) {
      m3u8Url = await _getYouTubeM3U8Url(url, ['720', '1080', '480', '360', '240']);
      if (m3u8Url != null) break;  // 如果获取成功，跳出循环
    }
    return m3u8Url;  // 返回解析到的 m3u8 地址或 null
  }

  // 获取普通 YouTube 视频的流媒体 URL，如果解析失败，返回 null
  Future<String?> _getYouTubeVideoUrl() async {
    try {
      var video = await yt.videos.get(url);  // 获取视频详细信息
      if (video.isLive) {
        // 如果是直播视频，调用获取直播流的函数
        return await _getYouTubeLiveStreamUrl();
      } else {
        // 获取视频的流媒体清单
        var manifest = await yt.videos.streamsClient.getManifest(video.id);
        // 按优先顺序获取最佳的视频流
        var streamInfo = _getBestStream(manifest, ['720p', '480p', '360p', '240p', '144p']);
        return streamInfo?.url.toString();  // 返回最佳视频流的 URL 或 null
      }
    } catch (e) {
      return null;  // 如果出错，返回 null
    }
  }

  // 根据指定的清晰度列表，获取最佳的视频流信息
  StreamInfo? _getBestStream(StreamManifest manifest, List<String> preferredQualities) {
    // 根据优先顺序查找匹配的流
    for (var quality in preferredQualities) {
      var streamInfo = manifest.muxed.firstWhere(
        (element) => element.qualityLabel == quality,
        orElse: () => manifest.muxed.last,  // 如果找不到，返回最后一个流
      );
      if (streamInfo != null) {
        return streamInfo;  // 返回匹配的流信息
      }
    }
    return null;  // 如果没有匹配的流，返回 null
  }

  // 获取 YouTube 视频的 m3u8 地址（用于直播流），根据不同的分辨率列表进行选择
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    try {
      // 向 YouTube 链接发送 HTTP GET 请求
      final response = await http.get(
        Uri.parse(youtubeUrl),
        headers: {'User-Agent': 'Mozilla/5.0'},  // 设置请求头，模拟浏览器请求
      ).timeout(Duration(seconds: 10));  // 设置请求超时时间为 10 秒

      if (response.statusCode == 200) {
        // 使用正则表达式查找 m3u8 地址
        final regex = RegExp(r'"hlsManifestUrl":"(https://[^"]+\.m3u8)"');
        final match = regex.firstMatch(response.body);

        if (match != null) {
          final indexM3u8Url = match.group(1);  // 获取到的 m3u8 地址
          if (indexM3u8Url != null) {
            // 调用函数选择最合适的质量 URL
            return await _getQualityM3U8Url(indexM3u8Url, preferredQualities);
          }
        }
      }
    } catch (e) {
      return null;  // 出错时返回 null
    }
    return null;  // 如果解析不到有效的 m3u8 地址，返回 null
  }

  // 根据 m3u8 清单中的分辨率，选择最合适的流 URL
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    try {
      // 请求 m3u8 文件，获取视频流的不同分辨率清单
      final response = await http.get(Uri.parse(indexM3u8Url));

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');  // 按行分割 m3u8 文件
        final qualityUrls = <String, String>{};

        // 遍历 m3u8 文件内容，提取分辨率和对应的 URL
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            final qualityLine = lines[i];
            final quality = _extractQuality(qualityLine);  // 从行中提取分辨率信息

            if (quality != null && i + 1 < lines.length) {
              final url = lines[i + 1];  // 获取对应的 URL
              qualityUrls[quality] = url;  // 保存质量和 URL 的映射
            }
          }
        }

        // 根据用户的分辨率优先顺序，选择匹配的流 URL
        for (var preferredQuality in preferredQualities) {
          if (qualityUrls.containsKey(preferredQuality)) {
            return qualityUrls[preferredQuality];  // 返回匹配的 URL
          }
        }

        if (qualityUrls.isNotEmpty) {
          return qualityUrls.values.first;  // 如果没有匹配，返回第一个 URL
        }
      }
    } catch (e) {
      return null;  // 出错时返回 null
    }
    return null;
  }

  // 从 m3u8 文件的清单行中提取视频质量（分辨率）
  String? _extractQuality(String extInfLine) {
    final regex = RegExp(r'RESOLUTION=\d+x(\d+)');  // 匹配分辨率的正则表达式
    final match = regex.firstMatch(extInfLine);

    if (match != null) {
      return match.group(1);  // 返回匹配到的分辨率值（如 720）
    }
    return null;  // 如果没有匹配到，返回 null
  }
}
