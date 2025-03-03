import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/lanzou_parser.dart';
import 'package:itvapp_live_tv/util/getm3u8.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

class StreamUrl {
  late final String url;
  final YoutubeExplode yt = YoutubeExplode(); 
  final HttpUtil _httpUtil = HttpUtil(); // 使用 HttpUtil 单例
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
  
  // 定义重定向规则，用@分隔不同的关键字
  static String rulesString = '.php@.asp@.jsp@.aspx';
  
  // 预定义容器类型集合，提高查找效率
  static final Set<String> validContainers = {'mp4', 'webm'};
  
  // 预编译的正则表达式，用于匹配特定 URL 和清单格式
  static final RegExp hlsManifestRegex = RegExp(r'"hlsManifestUrl":"(https://[^"]+\.m3u8)"');
  static final RegExp resolutionRegex = RegExp(r'RESOLUTION=\d+x(\d+)');
  static final RegExp extStreamInfRegex = RegExp(r'#EXT-X-STREAM-INF');

  StreamUrl(String inputUrl, {this.timeoutDuration = const Duration(seconds: 36)}) {
    // 在构造函数中处理 URL
    url = inputUrl.contains('\$') ? inputUrl.split('\$')[0].trim() : inputUrl;
  }
  
  // 获取媒体流 URL：根据 URL 类型进行相应处理并返回可用的流地址
  Future<String> getStreamUrl() async {
    if (_isDisposed) return 'ERROR';
    _completer = Completer<void>();
    try {
      // 检查是否为GetM3U8 URL
       if (isGetM3U8Url(url)) {
         final m3u8Url = await _handleGetM3U8Url(url);
           return m3u8Url;
      }
      
      // 判断是否为蓝奏云链接，若是则解析蓝奏云链接
      if (isLZUrl(url)) {
        if (isILanzouUrl(url)) {
          // 使用 API 处理 ilanzou.com 域名链接
          return 'https://lz.qaiu.top/parser?url=$url';
        } else {
          // 使用本地解析器处理其他蓝奏云链接
          final result = await LanzouParser.getLanzouUrl(url);
          if (result != 'ERROR') {
            return result;
          }
          return 'ERROR';
        }
      }
      
      // 检查 URL 是否为 YouTube 链接
      if (!isYTUrl(url)) {
        // 检查是否需要处理重定向
        if (needsRedirectCheck(url, rulesString)) {
          LogUtil.i('URL包含重定向规则关键字，检查重定向');
          return await checkRedirection(url); // 修改为使用 HttpUtil 的方法
        }
        return url;
      }
      
      // 选择处理 YouTube 直播或普通视频的任务
      final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
      
      // 尝试获取视频流，超时则重试
      try {
        final result = await task().timeout(timeoutDuration);
        if (result != 'ERROR') {
          return result;
        }
        LogUtil.e('首次获取视频流失败，准备重试');
      } catch (e) {
          LogUtil.e('首次获取视频流失败: ${e.toString()}，准备重试');
      }
      
      // 等待一秒后再次尝试获取视频流
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final result = await task().timeout(timeoutDuration);
        if (result != 'ERROR') {
          return result;
        }
        LogUtil.e('重试获取视频流失败');
        return 'ERROR';
      } catch (retryError) {
          LogUtil.e('重试获取视频流失败: ${retryError.toString()}');
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
  
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    
    // 给 completer 一个错误完成信号
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源已释放，任务被取消');
    }

    // 等待所有请求完成
    await _completer?.future.catchError((_) {});

    // 安全释放资源
    await LogUtil.safeExecute(() async {
      try {
        yt.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
      }

      // HttpUtil 是单例，无需手动关闭
    }, '关闭资源时发生错误');
  }

  /// 判断是否包含"getm3u8"
  bool isGetM3U8Url(String url) {
    return url.toLowerCase().contains('getm3u8');
  }
  
  /// 否则判断是否包含"lanzou"
  bool isLZUrl(String url) {
    // 如果包含分隔符，直接返回false
    if (url.contains('|')) {
      return false;
    }
    // 否则判断是否为蓝奏云链接
    return url.contains('lanzou');
  }
  
  // 判断是否为 ilanzou.com 域名的链接
  bool isILanzouUrl(String url) {
    return url.toLowerCase().contains('ilanzou.com');
  }
  
  // 判断是否为 YouTube 相关的链接
  bool isYTUrl(String url) {
    return url.contains('youtube') || url.contains('youtu.be') || url.contains('googlevideo');
  }
  
  // 验证给定 URL 是否为绝对 URL
  bool _isValidUrl(String url) {
    try {
      return Uri.parse(url).isAbsolute;
    } catch (e) {
      return false;
    }
  }

  // 监听网页获取 m3u8 的 URL
  Future<String> _handleGetM3U8Url(String url) async {
    if (_isDisposed) return 'ERROR';
    GetM3U8? detector;
    try {
      detector = GetM3U8(
        url: url,
        timeoutSeconds: timeoutDuration.inSeconds,
      );
      
      final result = await detector.getUrl();
      
      if (result.isEmpty) {
        LogUtil.e('GetM3U8返回空结果');
        return 'ERROR';
      }
      return result;

    } catch (e, stackTrace) {
      LogUtil.logError('GetM3U8处理失败', e, stackTrace);
      return 'ERROR';
    } finally {
      // 确保释放资源
      if (detector != null) {
        await detector.dispose(); 
      }
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
        final allVideoStreams = manifest.hls.whereType<HlsVideoStreamInfo>().toList();
        LogUtil.i('找到 ${allVideoStreams.length} 个HLS视频流');
        
        // 过滤有效的流
        final validStreams = allVideoStreams
            .where((s) => 
                _isValidUrl(s.url.toString()) &&
                s.container.name.toLowerCase() == 'm3u8')
            .toList();
        
        // 按照预定义的分辨率顺序查找视频流
        for (final res in resolutionMap.keys) {
          // 找出符合当前分辨率的流
          final matchingStreams = validStreams.where(
            (s) => s.qualityLabel.contains('${res}p')
          ).toList();
          
          // 如果找到了符合分辨率的流
          if (matchingStreams.isNotEmpty) {
            // 优先选择 avc1 编码的流
            selectedVideoStream = matchingStreams.firstWhere(
              (s) => s.codec.toString().toLowerCase().contains('avc1'),
              orElse: () => matchingStreams.first  // 如果没有avc1编码的流，使用第一个流
            );
            
            if (selectedVideoStream != null) {
              LogUtil.i('''找到 ${res}p 质量的视频流
                - tag: ${selectedVideoStream.tag}
                - qualityLabel: ${selectedVideoStream.qualityLabel}
                - videoCodec: ${selectedVideoStream.videoCodec}
                - codec: ${selectedVideoStream.codec}
                - container: ${selectedVideoStream.container}
                - bitrate: ${selectedVideoStream.bitrate.kiloBitsPerSecond} Kbps
                - videoQuality: ${selectedVideoStream.videoQuality}
                - videoResolution: ${selectedVideoStream.videoResolution}
                - framerate: ${selectedVideoStream.framerate}fps
                - url: ${selectedVideoStream.url}''');
              videoUrl = selectedVideoStream.url.toString();
              break;
            }
          }
        }
        
        // 获取音频流
        final audioStream = manifest.hls
            .whereType<HlsAudioStreamInfo>()
            .where((s) => 
                _isValidUrl(s.url.toString()) &&
                s.container.name.toLowerCase() == 'm3u8')
            .firstWhere(
                (s) => (s.bitrate.bitsPerSecond - 128000).abs() < 10000,
                orElse: () => manifest.hls.whereType<HlsAudioStreamInfo>().first
            );
            
        if (audioStream != null) {
          LogUtil.i('''找到 HLS音频流
            - bitrate: ${audioStream.bitrate.kiloBitsPerSecond} Kbps
            - codec: ${audioStream.codec}
            - container: ${audioStream.container}
            - tag: ${audioStream.tag}
            - url: ${audioStream.url}''');
          audioUrl = audioStream.url.toString();
        }
        
        // 如果找到了视频和音频流，生成并保存 m3u8 文件
        if (videoUrl != null && audioUrl != null && selectedVideoStream != null) {
          try {
            final directory = await getApplicationDocumentsDirectory();
            final fileName = 'master_youtube.m3u8';
            final filePath = '${directory.path}/$fileName';
            final file = File(filePath);
            
            // 从视频流的codec中提取编解码器信息
            final codecMatch = RegExp(r'codecs="([^"]+)"').firstMatch(selectedVideoStream.codec.toString());
            final codecs = codecMatch?.group(1) ?? 'avc1.4D401F,mp4a.40.2';
            
            final resolution = selectedVideoStream.videoResolution;
            final width = resolution.width;
            final height = resolution.height;
             
            final combinedM3u8 = '#EXTM3U\n'
                '#EXT-X-VERSION:3\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=${selectedVideoStream.bitrate.bitsPerSecond},'
                'RESOLUTION=${width}x$height,'
                'CODECS="$codecs",'  // 使用从视频流提取的编解码器信息（已含音频流编码），因为音频流没有提供编码信息
                'AUDIO="audio_group"\n'
                '$videoUrl\n'
                '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_group",NAME="Audio",'
                'DEFAULT=YES,AUTOSELECT=YES,URI="$audioUrl"';
            
            await file.writeAsString(combinedM3u8);
            LogUtil.i('成功保存m3u8文件到: $filePath');
            
            return filePath;
            
          } catch (e, stackTrace) {
            LogUtil.logError('保存m3u8文件失败', e, stackTrace);
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
      final m3u8Url = await _getYouTubeM3U8Url(url, resolutionMap.keys.toList());
      if (m3u8Url != null) {
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
      final response = await _httpUtil.getRequestWithResponse(
        youtubeUrl,
        options: Options(
          headers: _getRequestHeaders(),
          extra: {
            'connectTimeout': const Duration(seconds: 5),  // 连接超时
            'receiveTimeout': const Duration(seconds: 12), // 下载超时
          },
        ),
      ).timeout(timeoutDuration); // 保留外部超时控制
      if (_isDisposed || response == null) return null;

      if (response.statusCode == 200) {
        final match = hlsManifestRegex.firstMatch(response.data.toString());
        
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
      final response = await _httpUtil.getRequestWithResponse(
        indexM3u8Url,
        options: Options(
          extra: {
            'connectTimeout': const Duration(seconds: 5),  // 连接超时
            'receiveTimeout': const Duration(seconds: 12), // 下载超时
          },
        ),
      ).timeout(timeoutDuration); // 保留外部超时控制
      if (_isDisposed || response == null) return null;

      if (response.statusCode == 200) {
        final lines = response.data.toString().split('\n');
        final length = lines.length;  // 缓存长度避免重复访问
        final qualityUrls = <String, String>{};

        for (var i = 0; i < length; i++) {
          if (lines[i].contains('#EXT-X-STREAM-INF')) {
            final quality = _extractQuality(lines[i]);
            if (quality != null && i + 1 < length) {
              qualityUrls[quality] = lines[i + 1].trim();
            }
          }
          if (_isDisposed) return null;
        }

        // 按照预定义的分辨率顺序查找
        for (var quality in preferredQualities) {
          if (qualityUrls.containsKey(quality)) {
            return qualityUrls[quality];
          }
        }

        // 如果没有找到指定质量的流，返回第一个可用的流
        if (qualityUrls.isNotEmpty) {
          final firstQuality = qualityUrls.keys.first;
          LogUtil.i('未找到首选质量的直播流，使用 ${firstQuality}p');
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
    final match = resolutionRegex.firstMatch(extInfLine);
    return match?.group(1);
  }

  // 检查 URL 是否需要处理重定向
  bool needsRedirectCheck(String url, String rulesString) {
    final rules = rulesString.split('@');
    return rules.any((rule) => url.toLowerCase().contains(rule.toLowerCase()));
  }

  // 检查并处理URL重定向
  Future<String> checkRedirection(String url) async {
    // 设置固定超时时间为 5 秒连接超时和12秒接收超时
    const timeout = Duration(seconds: 18); // 外部超时
    
    try {
      // 第一次请求，禁用自动重定向
      final firstResp = await _httpUtil.getRequestWithResponse(
        url,
        options: Options(
          followRedirects: false, // 禁用 Dio 默认重定向
          extra: {
            'connectTimeout': const Duration(seconds: 5),  // 连接超时
            'receiveTimeout': const Duration(seconds: 12), // 下载超时
          },
        ),
      ).timeout(timeout);

      if (firstResp != null && firstResp.statusCode != null && firstResp.statusCode! >= 300 && firstResp.statusCode! < 400) {
        final location = firstResp.headers.value('location');
        if (location != null && location.isNotEmpty) {
          final redirectUri = Uri.parse(url).resolve(location);
          // 第二次请求
          final secondResp = await _httpUtil.getRequestWithResponse(
            redirectUri.toString(),
            options: Options(
              extra: {
                'connectTimeout': const Duration(seconds: 5),  // 连接超时
                'receiveTimeout': const Duration(seconds: 12), // 下载超时
              },
            ),
          ).timeout(timeout);
          // 最终拿到最终的 URL
          return secondResp?.requestOptions.uri.toString() ?? redirectUri.toString();
        }
      }
      // 没有跳转，就直接返回原始地址
      return url;
    } catch (e) {
      LogUtil.e('URL检查失败: $e');
      return url;
    }
  }

  // 获取 HTTP 请求需要的头信息，设置 User-Agent 来模拟浏览器访问
  Map<String, String> _getRequestHeaders() {
    return HeadersConfig.generateHeaders(url: url);
  }
}
