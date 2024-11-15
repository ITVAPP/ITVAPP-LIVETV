import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class StreamUrl {
  final String url;
  final YoutubeExplode yt = YoutubeExplode(); 
  final http.Client _client = http.Client(); 
  bool _isDisposed = false; 
  Completer<void>? _completer; 
  final Duration timeoutDuration;
  
  // 预定义视频分辨率映射表，用于提高性能
  static final Map<String, (int, int)> resolutionMap = {
    '720': (1280, 720),
    '1080': (1920, 1080),
    '480': (854, 480),
    '360': (640, 360)
  };
  
  // 预定义容器类型集合，提高查找效率
  static final Set<String> validContainers = {'mp4', 'webm'};
  
  // 预编译的正则表达式
  static final RegExp hlsManifestRegex = RegExp(r'"hlsManifestUrl":"(https://[^"]+\.m3u8)"');
  static final RegExp resolutionRegex = RegExp(r'RESOLUTION=\d+x(\d+)');
  static final RegExp extStreamInfRegex = RegExp(r'#EXT-X-STREAM-INF');

  StreamUrl(this.url, {this.timeoutDuration = const Duration(seconds: 18)});
  
// 获取媒体流 URL：根据不同类型的 URL 进行相应处理并返回可用的流地址
  Future<String> getStreamUrl() async {
    if (_isDisposed) return 'ERROR';
    _completer = Completer<void>();
    try {
      if (isLZUrl(url)){
        return 'https://lz.qaiu.top/parser?url=$url'; 
      } 
      
      if (!isYTUrl(url)) {
        return url;
      } 
      
      final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
      
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
      
      await Future.delayed(const Duration(seconds: 1));
      
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
      return 'ERROR';
    } finally {
      if (!_isDisposed) {
        _completer?.complete();
      }
      _completer = null;
    }
  }
  
void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源已释放，任务被取消');
    }

    LogUtil.safeExecute(() {
      try {
        yt.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
      }

      try {
        _client.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 HTTP 客户端时发生错误', e, stackTrace);
      }
    }, '关闭资源时发生错误');
  }

  bool isLZUrl(String url) {
    return url.contains('lanzou');
  }
  
  bool isYTUrl(String url) {
    return url.contains('youtube') || url.contains('youtu.be') || url.contains('googlevideo');
  }

  bool _isValidUrl(String url) {
    try {
      return Uri.parse(url).isAbsolute;
    } catch (e) {
      return false;
    }
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

String? videoUrl;
String? audioUrl;
HlsVideoStreamInfo? selectedVideoStream;

// 优先尝试获取 HLS 流
if (manifest.hls.isNotEmpty) {
  // 获取视频流
  final hlsStream = manifest.hls
      .whereType<HlsVideoStreamInfo>()
      .where((s) => 
          _isValidUrl(s.url.toString()) &&
          s.container.name.toLowerCase() == 'm3u8' &&
          s.videoCodec != null)
      .firstWhere(
          (s) => s.qualityLabel.contains('720p'),
          orElse: () => null
      );

  if (hlsStream != null) {
    videoUrl = hlsStream.url.toString();
    selectedVideoStream = hlsStream;
  }

  // 获取音频流
  final audioStream = manifest.hls
      .whereType<HlsAudioStreamInfo>()
      .where((s) => 
          _isValidUrl(s.url.toString()) &&
          s.container.name.toLowerCase() == 'm3u8' &&
          s.audioCodec != null)
      .firstWhere(
          (s) => (s.bitrate.bitsPerSecond - 128000).abs() < 10000,
          orElse: () => manifest.hls.whereType<HlsAudioStreamInfo>().first
      );

  if (audioStream != null) {
    LogUtil.i('''找到 HLS音频流，比特率: ${audioStream.bitrate.kiloBitsPerSecond} Kbps''');
    audioUrl = audioStream.url.toString();
  }

  // 如果找到了视频和音频流，生成并保存 master playlist
  if (videoUrl != null && audioUrl != null && selectedVideoStream != null) {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/master_youtube.m3u8');

      final resolution = selectedVideoStream.qualityLabel.replaceAll('p', '');
      final (width, height) = resolutionMap[resolution] ?? (1280, 720);
         
      final combinedM3u8 = '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=${selectedVideoStream.bitrate.bitsPerSecond},'
          'RESOLUTION=${width}x$height,CODECS="${selectedVideoStream.videoCodec ?? 'avc1.42001f'},${audioStream.audioCodec ?? 'mp4a.40.2'}",'
          'AUDIO="audio_group"\n'
          '$videoUrl\n'
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_group",NAME="Audio",'
          'DEFAULT=YES,AUTOSELECT=YES,URI="$audioUrl"';
             
      LogUtil.i('''生成新的m3u8文件：\n$combinedM3u8''');
      
      await file.writeAsString(combinedM3u8);
      return file.path;
      
    } catch (e) {
      LogUtil.logError('保存m3u8文件失败', e);
      return 'ERROR';
    }
  }
  LogUtil.i('HLS流中未找到完整的音视频流');
} else {
  LogUtil.i('没有可用的 HLS 流');
}

// 如果没有合适的 HLS 流，尝试获取普通混合流
var streamInfo = _getBestMuxedStream(manifest);
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

// 获取最佳的普通混合流，优先选择 MP4 格式
StreamInfo? _getBestMuxedStream(StreamManifest manifest) {
  if (manifest.muxed.isEmpty) {
    LogUtil.i('没有可用的混合流');
    return null;
  }

  try {
    LogUtil.i('查找普通混合流');
    
    // 直接从manifest.muxed中获取有效流
    final validStreams = manifest.muxed
        .where((s) => _isValidUrl(s.url.toString()))
        .toList();
    
    if (validStreams.isEmpty) {
      LogUtil.i('未找到有效URL的混合流');
      return null;
    }
    
    // 优先选择MP4格式
    final streamInfo = validStreams.firstWhere(
      (s) => s.container.name.toLowerCase() == 'mp4',
      orElse: () => validStreams.first
    );
    
    LogUtil.i('找到 ${streamInfo.container.name} 格式混合流');
    return streamInfo;

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
    final response = await _client.get(
      Uri.parse(youtubeUrl),
      headers: _getRequestHeaders(),
    ).timeout(timeoutDuration);
    if (_isDisposed) return null;

    if (response.statusCode == 200) {
      final match = hlsManifestRegex.firstMatch(response.body);
      
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
    final response = await _client.get(Uri.parse(indexM3u8Url))
        .timeout(timeoutDuration);
    if (_isDisposed) return null;

    if (response.statusCode == 200) {
      final lines = response.body.split('\n');
      final length = lines.length;  // 缓存长度避免重复访问
      final qualityUrls = <String, String>{};

      for (var i = 0; i < length; i++) {
        if (lines[i].contains('#EXT-X-STREAM-INF')) {
          final quality = _extractQuality(lines[i]);
          if (quality != null && i + 1 < length) {
            qualityUrls[quality] = lines[i + 1];
          }
        }
        if (_isDisposed) return null;
      }

      // 按照优先级查找指定质量的流
      for (var quality in preferredQualities) {
        if (qualityUrls.containsKey(quality)) {
          return qualityUrls[quality];
        }
      }

      return qualityUrls.values.firstOrNull;
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
  final match = resolutionRegex.firstMatch(extInfLine);
  return match?.group(1);
}

// 获取 HTTP 请求需要的头信息，设置 User-Agent 来模拟浏览器访问
Map<String, String> _getRequestHeaders() {
  return {
    HttpHeaders.userAgentHeader: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };
}
}
