import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
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
  final HttpUtil _httpUtil = HttpUtil(); // 使用 HttpUtil 单例，无需释放
  Completer<void>? _completer;
  final Duration timeoutDuration;
  late final CancelToken _cancelToken; // 实例级的 CancelToken，用于取消所有 HTTP 请求

  // 定义常量
  static const String ERROR_RESULT = 'ERROR';
  /// 默认任务超时时间（单位：秒），用于设置获取流地址的总体超时限制
  static const Duration DEFAULT_TIMEOUT = Duration(seconds: 32);
  /// HTTP 连接超时时间（单位：秒），用于限制建立连接的最大等待时间
  static const Duration CONNECT_TIMEOUT = Duration(seconds: 5);
  /// HTTP 数据接收超时时间（单位：秒），用于限制接收响应的最大等待时间
  static const Duration RECEIVE_TIMEOUT = Duration(seconds: 12);
  /// 重试任务之间的延迟时间（单位：秒），用于在首次获取流失败后等待一段时间再重试
  static const Duration RETRY_DELAY = Duration(seconds: 1);

  // 预定义视频分辨率映射表，使用 const 确保不可变，提升性能
  static const Map<String, (int, int)> resolutionMap = {
    '720': (1280, 720),
    '1080': (1920, 1080),
    '480': (854, 480),
    '360': (640, 360)
  };

  // 定义重定向规则，用@分隔不同的关键字
  static String rulesString = '.php@.asp@.jsp@.aspx';

  // 预定义容器类型集合，使用 const 确保不可变，提升性能
  static const Set<String> validContainers = {'mp4', 'webm'};

  // 预编译的正则表达式，用于匹配特定 URL 和清单格式
  static final RegExp hlsManifestRegex = RegExp(r'"hlsManifestUrl":"(https://[^"]+.m3u8)"');
  static final RegExp resolutionRegex = RegExp(r'RESOLUTION=\d+x(\d+)');
  static final RegExp extStreamInfRegex = RegExp(r'#EXT-X-STREAM-INF');

  /// 构造函数，初始化 StreamUrl 实例
  StreamUrl(String inputUrl, {Duration timeoutDuration = DEFAULT_TIMEOUT})
      : timeoutDuration = timeoutDuration {
    url = inputUrl.contains('\$') ? inputUrl.split('\$')[0].trim() : inputUrl;
    _cancelToken = CancelToken(); // 初始化实例级的 CancelToken
  }

  // 检查是否已取消，减少冗余判断
  bool _isCancelled() => _cancelToken.isCancelled;

  // 获取媒体流 URL：根据 URL 类型进行相应处理并返回可用的流地址
  Future<String> getStreamUrl() async {
    if (_isCancelled()) return 'ERROR'; // 使用封装方法检查取消状态
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
          final result = await LanzouParser.getLanzouUrl(url, cancelToken: _cancelToken);
          if (result != 'ERROR') {
            return result;
          }
          return 'ERROR';
        }
      }

      // 检查 URL 是否为 YouTube 链接
      if (!isYTUrl(url)) {
        return url;
      }

      // 选择处理 YouTube 直播或普通视频的任务
      final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;

      // 重试逻辑
      return await _retryTask(task);
    } catch (e, stackTrace) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        LogUtil.i('解析任务被取消');
      } else {
        LogUtil.logError('获取视频流地址时发生错误', e, stackTrace);
      }
      return 'ERROR';
    } finally {
      _completeSafely(); // 确保 _completer 在所有情况下都被释放
    }
  }

  /// 重试逻辑：对指定任务进行重试，最多尝试两次，带有超时和取消检查
  Future<String> _retryTask(Future<String> Function() task) async {
    // 首次尝试
    try {
      final result = await task().timeout(timeoutDuration);
      if (result != ERROR_RESULT) return result;
      LogUtil.e('首次获取视频流失败，准备重试');
    } catch (e) {
      if (_isCancelled()) {
        LogUtil.i('首次任务被取消，不进行重试');
        return ERROR_RESULT;
      }
      LogUtil.e('首次获取视频流失败: ${e.toString()}，准备重试');
    }

    // 提前检查是否取消，避免无意义的延迟和重试
    if (_isCancelled()) {
      LogUtil.i('重试前任务已取消，直接返回');
      return ERROR_RESULT;
    }

    // 延迟后重试
    await Future.delayed(RETRY_DELAY);
    try {
      final result = await task().timeout(timeoutDuration);
      return result != ERROR_RESULT ? result : ERROR_RESULT;
    } catch (retryError) {
      if (_isCancelled()) {
        LogUtil.i('重试任务被取消');
        return ERROR_RESULT;
      }
      LogUtil.e('重试获取视频流失败: ${retryError.toString()}');
      return ERROR_RESULT;
    }
  }

  // 安全完成 Completer，避免内存泄漏
  void _completeSafely() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  /// 释放资源：确保所有异步任务完成并取消未完成的请求
  Future<void> dispose() async {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源已释放，任务被取消');
    }

    // 合并资源释放逻辑为单一异步任务，减少开销
    await Future.wait([
      _completer?.future.catchError((e) {
        LogUtil.e('Completer 完成时发生错误: $e');
      }) ?? Future.value(),
      Future(() async {
        _cancelToken.cancel('StreamUrl disposed');
        LogUtil.i('已取消所有未完成的 HTTP 请求');
        try {
          yt.close(); // 确保在 dispose 中统一释放 yt
        } catch (e, stackTrace) {
          LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
        }
      }),
    ]);
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

  // 验证给定 URL 是否为绝对 URL，优化为单次解析
  bool _isValidUrl(String url) {
    try {
      return Uri.parse(url).isAbsolute;
    } catch (e) {
      return false;
    }
  }

  // 监听网页获取 m3u8 的 URL，传递 _cancelToken
  Future<String> _handleGetM3U8Url(String url) async {
    if (_isCancelled()) return 'ERROR'; // 使用封装方法检查取消状态
    GetM3U8? detector;
    try {
      detector = GetM3U8(
        url: url,
        timeoutSeconds: timeoutDuration.inSeconds,
        cancelToken: _cancelToken,
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
      if (detector != null) {
        await detector.dispose();
      }
    }
  }

  // 获取普通 YouTube 视频的流媒体 URL
  Future<String> _getYouTubeVideoUrl() async {
    if (_isCancelled()) return 'ERROR'; // 使用封装方法检查取消状态
    try {
      var video = await yt.videos.get(url);
      if (_isCancelled()) {
        LogUtil.i('解析视频信息后任务被取消');
        return 'ERROR';
      }

      var manifest = await yt.videos.streams.getManifest(video.id);
      if (_isCancelled()) {
        LogUtil.i('解析流清单后任务被取消');
        return 'ERROR';
      }
      LogUtil.i('''
======= Manifest 流信息 =======
HLS流数量: ${manifest.hls.length}
混合流数量: ${manifest.muxed.length} ===============================''');
      LogUtil.i('manifest 的格式化信息: ${manifest.toString()}');
      String? videoUrl;
      String? audioUrl;
      HlsVideoStreamInfo? selectedVideoStream;

      // 并行获取 HLS 视频流和音频流，提升效率
      if (manifest.hls.isNotEmpty) {
        final allVideoStreams = manifest.hls.whereType<HlsVideoStreamInfo>().toList();
        LogUtil.i('找到 ${allVideoStreams.length} 个HLS视频流');

        final validStreams = allVideoStreams
            .where((s) =>
                _isValidUrl(s.url.toString()) && s.container.name.toLowerCase() == 'm3u8')
            .toList();

        final videoFuture = Future(() async {
          for (final res in resolutionMap.keys) {
            final matchingStreams = validStreams
                .where((s) => s.qualityLabel.contains('${res}p'))
                .toList();

            if (matchingStreams.isNotEmpty) {
              selectedVideoStream = matchingStreams.firstWhere(
                (s) => s.codec.toString().toLowerCase().contains('avc1'),
                orElse: () => matchingStreams.first,
              );
              if (selectedVideoStream != null) {
                LogUtil.i('''找到 ${res}p 质量的视频流
tag: ${selectedVideoStream!.tag}
qualityLabel: ${selectedVideoStream!.qualityLabel}
videoCodec: ${selectedVideoStream!.videoCodec}
codec: ${selectedVideoStream!.codec}
container: ${selectedVideoStream!.container}
bitrate: ${selectedVideoStream!.bitrate.kiloBitsPerSecond} Kbps
videoQuality: ${selectedVideoStream!.videoQuality}
videoResolution: ${selectedVideoStream!.videoResolution}
framerate: ${selectedVideoStream!.framerate}fps
url: ${selectedVideoStream!.url}''');
                videoUrl = selectedVideoStream!.url.toString();
                return true;
              }
            }
          }
          return false;
        });

        final audioFuture = Future(() async {
          final audioStream = manifest.hls
              .whereType<HlsAudioStreamInfo>()
              .where((s) =>
                  _isValidUrl(s.url.toString()) && s.container.name.toLowerCase() == 'm3u8')
              .firstWhere(
                (s) => (s.bitrate.bitsPerSecond - 128000).abs() < 10000,
                orElse: () => manifest.hls.whereType<HlsAudioStreamInfo>().first,
              );

          if (audioStream != null) {
            LogUtil.i('''找到 HLS音频流
bitrate: ${audioStream.bitrate.kiloBitsPerSecond} Kbps
codec: ${audioStream.codec}
container: ${audioStream.container}
tag: ${audioStream.tag}
url: ${audioStream.url}''');
            audioUrl = audioStream.url.toString();
            return true;
          }
          return false;
        });

        final results = await Future.wait([videoFuture, audioFuture]);
        if (results.every((r) => r) && videoUrl != null && audioUrl != null && selectedVideoStream != null) {
          try {
            final result = await _generateM3u8File(selectedVideoStream!, audioUrl!);
            if (result != 'ERROR') {
              return result;
            }
          } catch (e, stackTrace) {
            LogUtil.logError('生成 m3u8 文件失败', e, stackTrace);
            return 'ERROR';
          }
        }
        LogUtil.i('HLS流中未找到完整的音视频流');
      } else {
        LogUtil.i('没有可用的 HLS 流');
      }

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

  /// 生成并保存 m3u8 文件：将视频流和音频流合并为本地 m3u8 文件
  Future<String> _generateM3u8File(HlsVideoStreamInfo videoStream, String audioUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'master_youtube.m3u8';
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final codecMatch = RegExp(r'codecs="([^"]+)"').firstMatch(videoStream.codec.toString());
      final codecs = codecMatch?.group(1) ?? 'avc1.4D401F,mp4a.40.2';

      // 缓存 resolution，避免重复计算
      final resolution = videoStream.videoResolution;
      final width = resolution.width;
      final height = resolution.height;

      final combinedM3u8 = '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=${videoStream.bitrate.bitsPerSecond},'
          'RESOLUTION=${width}x$height,'
          'CODECS="$codecs",'
          'AUDIO="audio_group"\n'
          '${videoStream.url}\n'
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

  // 获取最佳的普通混合流，优先选择 MP4 格式
  StreamInfo? _getBestMuxedStream(StreamManifest manifest) {
    if (manifest.muxed.isEmpty) {
      LogUtil.i('没有可用的混合流');
      return null;
    }

    try {
      LogUtil.i('查找普通混合流');

      // 缓存过滤结果，避免重复遍历
      final validStreams = manifest.muxed
          .where((s) => _isValidUrl(s.url.toString()))
          .toList();

      if (validStreams.isEmpty) {
        LogUtil.i('未找到有效URL的混合流');
        return null;
      }

      final streamInfo = validStreams.firstWhere(
        (s) => s.container.name.toLowerCase() == 'mp4',
        orElse: () => validStreams.first,
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
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取直播流');
      return 'ERROR';
    }
    LogUtil.i('开始获取 YouTube 直播流，URL: $url');
    try {
      final m3u8Url = await _getYouTubeM3U8Url(url, resolutionMap.keys.toList());
      if (m3u8Url != null) {
        LogUtil.i('成功获取直播流地址: $m3u8Url');
        return m3u8Url;
      }
      LogUtil.e('未能获取到有效的直播流地址');
      return 'ERROR';
    } catch (e, stackTrace) {
      if (!_isCancelled()) {
        LogUtil.logError('获取 YT 直播流地址时发生错误', e, stackTrace);
      }
      return 'ERROR';
    }
  }

  /// 获取 YouTube 直播的 m3u8 清单地址：从网页中提取 HLS 清单 URL
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取 M3U8 URL');
      return null;
    }
    LogUtil.i('开始获取 HLS 清单地址，URL: $youtubeUrl，发送 GET 请求获取直播页面内容');
    try {
      final response = await _httpUtil.getRequestWithResponse(
        youtubeUrl,
        options: Options(
          extra: {
            'connectTimeout': CONNECT_TIMEOUT,
            'receiveTimeout': RECEIVE_TIMEOUT,
          },
        ),
        cancelToken: _cancelToken,
      ).timeout(timeoutDuration);
      if (_isCancelled()) {
        LogUtil.i('对象已释放，停止处理响应');
        return null;
      }
      if (response == null) {
        LogUtil.e('HTTP 请求返回空响应');
        return null;
      }

      LogUtil.i('收到响应，状态码: ${response.statusCode}');
      if (response.statusCode == 200) {
        String responseData = response.data.toString();
        LogUtil.i('开始解析页面内容以提取 hlsManifestUrl');
        const styleEndMarker = '</style>';
        int lastStyleEnd = responseData.lastIndexOf(styleEndMarker);
        if (lastStyleEnd != -1) {
          responseData = responseData.substring(lastStyleEnd + styleEndMarker.length);
          LogUtil.i('找到最后一个 </style>，从其后开始查找 hlsManifestUrl');
        } else {
          LogUtil.i('未找到 </style>，使用完整响应数据');
        }

        const marker = '"hlsManifestUrl":"';
        final start = responseData.indexOf(marker);
        if (start == -1) {
          LogUtil.e('未在页面内容中匹配到 hlsManifestUrl');
          return null;
        }

        final urlStart = start + marker.length;
        final urlEnd = responseData.indexOf('"', urlStart);
        if (urlEnd == -1) {
          LogUtil.e('hlsManifestUrl 提取结果为空');
          return null;
        }

        final indexM3u8Url = responseData.substring(urlStart, urlEnd);
        if (indexM3u8Url.endsWith('.m3u8')) {
          LogUtil.i('成功提取 hlsManifestUrl: $indexM3u8Url，开始解析质量并选择直播流地址');
          final qualityUrl = await _getQualityM3U8Url(indexM3u8Url, preferredQualities);
          if (qualityUrl != null) {
            LogUtil.i('成功选择质量直播流地址: $qualityUrl');
            return qualityUrl;
          } else {
            LogUtil.e('未能从清单中选择有效的质量直播流地址');
            return null;
          }
        } else {
          LogUtil.e('hlsManifestUrl 提取结果无效');
          return null;
        }
      } else {
        LogUtil.e('HTTP 请求失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      if (!_isCancelled()) {
        // 细化异常处理
        if (e is DioException) {
          LogUtil.logError('HTTP 请求失败', e, stackTrace);
        } else if (e is TimeoutException) {
          LogUtil.logError('请求超时', e, stackTrace);
        } else {
          LogUtil.logError('获取 M3U8 URL 时发生未知错误', e, stackTrace);
        }
      }
      return null;
    }
  }

  /// 从 m3u8 清单中选择指定质量的流地址：根据首选分辨率解析 HLS 清单
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取质量 M3U8 URL');
      return null;
    }
    LogUtil.i(
        '开始解析 HLS 清单以选择质量，URL: $indexM3u8Url，首选分辨率顺序: $preferredQualities，发送 GET 请求获取 HLS 清单内容');
    try {
      final response = await _httpUtil.getRequestWithResponse(
        indexM3u8Url,
        options: Options(
          extra: {
            'connectTimeout': CONNECT_TIMEOUT,
            'receiveTimeout': RECEIVE_TIMEOUT,
          },
        ),
        cancelToken: _cancelToken,
      ).timeout(timeoutDuration);
      if (_isCancelled()) {
        LogUtil.i('对象已释放，停止处理响应');
        return null;
      }
      if (response == null) {
        LogUtil.e('HTTP 请求返回空响应');
        return null;
      }

      LogUtil.i('收到响应，状态码: ${response.statusCode}');
      if (response.statusCode == 200) {
        String responseData = response.data.toString();
        LogUtil.i('开始解析 HLS 清单内容');
        final lines = responseData.split('\n');
        final length = lines.length;
        final qualityUrls = <String, String>{};

        // 使用预编译正则表达式优化循环效率
        for (var i = 0; i < length; i++) {
          if (extStreamInfRegex.hasMatch(lines[i])) {
            final quality = _extractQuality(lines[i]);
            if (quality != null && i + 1 < length) {
              qualityUrls[quality] = lines[i + 1].trim();
              LogUtil.i('找到分辨率 ${quality}p 的流地址: ${qualityUrls[quality]}');
            }
          }
          if (_isCancelled()) {
            LogUtil.i('对象已释放，停止解析清单');
            return null;
          }
        }
        LogUtil.i('解析完成，发现的分辨率和流地址: $qualityUrls');
        // 使用 Map 键值查找替代线性搜索
        for (var quality in preferredQualities) {
          if (qualityUrls.containsKey(quality)) {
            LogUtil.i('选择分辨率 ${quality}p 的流地址: ${qualityUrls[quality]}');
            return qualityUrls[quality];
          }
        }

        if (qualityUrls.isNotEmpty) {
          final firstQuality = qualityUrls.keys.first;
          LogUtil.i(
              '未找到首选质量的直播流，使用 ${firstQuality}p，返回流地址: ${qualityUrls.values.first}');
          return qualityUrls.values.first;
        } else {
          LogUtil.e('HLS 清单中未找到任何有效的子流地址');
          return null;
        }
      } else {
        LogUtil.e('HTTP 请求失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      if (!_isCancelled()) {
        // 细化异常处理
        if (e is DioException) {
          LogUtil.logError('HTTP 请求失败', e, stackTrace);
        } else if (e is TimeoutException) {
          LogUtil.logError('请求超时', e, stackTrace);
        } else {
          LogUtil.logError('获取质量 M3U8 URL 时发生未知错误', e, stackTrace);
        }
      }
      return null;
    }
  }

  /// 从 m3u8 清单行提取视频质量信息：优化为字符串操作替代正则表达式
  String? _extractQuality(String extInfLine) {
    if (_isCancelled()) return null;
    const marker = 'RESOLUTION=';
    final start = extInfLine.indexOf(marker);
    if (start == -1) return null;

    final resolutionStart = start + marker.length;
    final resolutionEnd = extInfLine.indexOf(',', resolutionStart);
    final resolution = resolutionEnd != -1
        ? extInfLine.substring(resolutionStart, resolutionEnd)
        : extInfLine.substring(resolutionStart);

    final parts = resolution.split('x');
    if (parts.length != 2) return null;
    return parts[1];
  }

  // 检查 URL 是否需要处理重定向
  bool needsRedirectCheck(String url, String rulesString) {
    final rules = rulesString.split('@');
    return rules.any((rule) => url.toLowerCase().contains(rule.toLowerCase()));
  }
}
