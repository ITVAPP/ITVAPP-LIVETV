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

// 流媒体URL解析类，支持多种类型URL解析
class StreamUrl {
  late final String url; // 流媒体地址
  final YoutubeExplode yt = YoutubeExplode(); // YouTube解析实例
  final HttpUtil _httpUtil = HttpUtil(); // HTTP工具单例
  Completer<void>? _completer; // 异步任务完成器
  final Duration timeoutDuration; // 单次解析超时时间
  final CancelToken cancelToken; // 外部取消令牌，仅传递使用
  int _retryCount = 0; // YouTube解析重试计数

  static GetM3U8? _currentDetector; // 当前GetM3U8实例
  static final Map<String, (String, DateTime)> _urlCache = {}; // URL缓存
  static bool _cleanupScheduled = false; // 缓存清理标志
  static const int _MAX_CACHE_ENTRIES = 100; // 缓存最大条目数
  static const int _CACHE_EXPIRY_MINUTES = 5; // 缓存有效期（分钟）

  // 默认HTTP请求配置
  static final Options _defaultOptions = Options(
    extra: {
      'connectTimeout': CONNECT_TIMEOUT,
      'receiveTimeout': RECEIVE_TIMEOUT,
    },
  );

  static const String ERROR_RESULT = 'ERROR'; // 错误结果常量
  static const Duration DEFAULT_TIMEOUT = Duration(seconds: 15); // YouTube解析超时时间
  static const int maxRetryCount = 1; // 最大重试次数
  static const Duration retryDelay = Duration(milliseconds: 500); // 重试延迟
  static const Duration CONNECT_TIMEOUT = Duration(seconds: 5); // HTTP连接超时
  static const Duration RECEIVE_TIMEOUT = Duration(seconds: 12); // HTTP接收超时

  // 视频分辨率映射表
  static const Map<String, (int, int)> resolutionMap = {
    '720': (1280, 720),
    '1080': (1920, 1080),
    '480': (854, 480),
    '360': (640, 360)
  };

  static final RegExp hlsManifestRegex = RegExp(r'"hlsManifestUrl":"(https://[^"]+.m3u8)"'); // HLS清单正则
  static final RegExp extStreamInfRegex = RegExp(r'#EXT-X-STREAM-INF'); // M3U8流信息正则

  bool _disposed = false; // 资源释放标记

  // 初始化URL和超时，接收外部取消令牌
  StreamUrl(String inputUrl, {
    Duration timeoutDuration = DEFAULT_TIMEOUT,
    required this.cancelToken,
  }) : timeoutDuration = timeoutDuration {
    url = inputUrl.contains('\$') ? inputUrl.split('\$')[0].trim() : inputUrl;
    _ensureCacheCleanup();
  }

  // 规范化URL，排序查询参数确保一致性
  static String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.isEmpty) return url;
      final sortedParams = Map.fromEntries(
        uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      final normalizedUri = Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: sortedParams,
        fragment: uri.fragment,
      );
      return normalizedUri.toString();
    } catch (e) {
      return url;
    }
  }

  // 启动周期性缓存清理任务
  static void _ensureCacheCleanup() {
    if (!_cleanupScheduled) {
      _cleanupScheduled = true;
      Timer.periodic(Duration(minutes: _CACHE_EXPIRY_MINUTES), (_) => _cleanCache());
    }
  }

  // 清理过期或超量缓存条目
  static void _cleanCache() {
    final now = DateTime.now();
    // 移除过期缓存
    _urlCache.removeWhere((_, value) => now.difference(value.$2).inMinutes > _CACHE_EXPIRY_MINUTES);
    
    // 若缓存超限，保留较新条目
    if (_urlCache.length > _MAX_CACHE_ENTRIES) {
      final entriesToKeep = _MAX_CACHE_ENTRIES ~/ 2;
      final entries = _urlCache.entries.toList();
      _urlCache.clear();
      for (var i = entries.length - entriesToKeep; i < entries.length; i++) {
        _urlCache[entries[i].key] = entries[i].value;
      }
    }
  }

  // 检查任务是否取消
  bool _isCancelled() => _disposed || cancelToken.isCancelled;

  // 获取流媒体URL，支持多种类型
  Future<String> getStreamUrl() async {
    if (_isCancelled()) return ERROR_RESULT;
    _completer = Completer<void>();
    
    String? normalizedUrl;
    
    // 检查YouTube URL缓存
    if (isYTUrl(url)) {
      normalizedUrl = _normalizeUrl(url);
      if (_urlCache.containsKey(normalizedUrl)) {
        final (cachedResult, timestamp) = _urlCache[normalizedUrl]!;
        if (DateTime.now().difference(timestamp).inMinutes < _CACHE_EXPIRY_MINUTES &&
            cachedResult != ERROR_RESULT) {
          LogUtil.i('命中缓存URL: $url');
          return cachedResult;
        }
      }
    }
    
    try {
      String result;
      if (isGetM3U8Url(url)) {
        result = await _handleGetM3U8Url(url);
      } else if (isLZUrl(url)) {
        result = isILanzouUrl(url)
            ? 'https://lz.qaiu.top/parser?url=$url'
            : await LanzouParser.getLanzouUrl(url, cancelToken: cancelToken);
      } else if (isYTUrl(url)) {
        result = await _handleYouTubeWithRetry();
      } else {
        result = url;
      }
      
      // 缓存YouTube解析结果
      if (result != ERROR_RESULT && isYTUrl(url)) {
        normalizedUrl ??= _normalizeUrl(url);
        _urlCache[normalizedUrl] = (result, DateTime.now());
      }
      
      return result;
    } catch (e, stackTrace) {
      return _handleError('获取流地址失败', e, stackTrace);
    } finally {
      _completeSafely();
    }
  }

  // 处理解析错误
  String _handleError(String message, dynamic error, StackTrace? stackTrace) {
    if (error is DioException && error.type == DioExceptionType.cancel) {
      LogUtil.i('解析任务已取消');
    } else {
      LogUtil.logError(message, error, stackTrace);
    }
    return ERROR_RESULT;
  }

  // 处理YouTube解析重试逻辑
  Future<String> _handleYouTubeWithRetry() async {
    _retryCount = 0;
    while (_retryCount <= maxRetryCount) {
      if (_isCancelled()) return ERROR_RESULT;
      
      try {
        final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
        final result = await task().timeout(timeoutDuration);
        if (result != ERROR_RESULT) {
          LogUtil.i('YouTube解析成功，尝试：${_retryCount + 1}/${maxRetryCount + 1}');
          return result;
        }
      } catch (e) {
        if (_isCancelled()) return ERROR_RESULT;
        LogUtil.e('YouTube解析失败，尝试：${_retryCount + 1}/${maxRetryCount + 1}，错误：$e');
      }
      
      if (_retryCount < maxRetryCount) {
        _retryCount++;
        LogUtil.i('YouTube重试：$_retryCount/$maxRetryCount，延迟${retryDelay.inMilliseconds}ms');
        await Future.delayed(retryDelay);
      } else {
        break;
      }
    }
    
    LogUtil.e('YouTube解析达到最大重试次数');
    return ERROR_RESULT;
  }

  // 安全完成异步任务
  void _completeSafely() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  // 释放资源
  Future<void> dispose() async {
    if (_disposed) {
      LogUtil.i('StreamUrl已释放，跳过');
      return;
    }
    _disposed = true;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError('资源释放，任务取消');
    }
    await _currentDetector?.dispose();
    _currentDetector = null;
    try {
      yt.close();
    } catch (e, stackTrace) {
      LogUtil.logError('释放YT实例失败', e, stackTrace);
    }
    try {
      await _completer?.future;
    } catch (e) {}
    LogUtil.i('StreamUrl资源释放完成');
  }

  // 判断是否为YouTube URL
  bool isYTUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('youtube') || lowerUrl.contains('youtu.be') || lowerUrl.contains('googlevideo');
  }

  // 判断是否为GetM3U8 URL
  bool isGetM3U8Url(String url) => url.toLowerCase().contains('getm3u8');

  // 判断是否为蓝奏云URL
  bool isLZUrl(String url) => !url.contains('|') && url.contains('lanzou');

  // 判断是否为ilanzou.com URL
  bool isILanzouUrl(String url) => url.toLowerCase().contains('ilanzou.com');

  // 验证URL是否为绝对地址
  bool _isValidUrl(String url) {
    try {
      return Uri.parse(url).isAbsolute;
    } catch (e) {
      return false;
    }
  }

  // 处理GetM3U8 URL，获取流地址
  Future<String> _handleGetM3U8Url(String url) async {
    if (_isCancelled()) return ERROR_RESULT;
    await _currentDetector?.dispose();
    _currentDetector = null;
    GetM3U8? detector;
    try {
      detector = GetM3U8(url: url, cancelToken: cancelToken);
      _currentDetector = detector;
      final result = await detector.getUrl();
      if (result.isEmpty) {
        LogUtil.e('GetM3U8返回空结果');
        return ERROR_RESULT;
      }
      return result;
    } catch (e, stackTrace) {
      return _handleError('GetM3U8处理失败', e, stackTrace);
    } finally {
      if (detector != null && detector == _currentDetector) {
        await detector.dispose();
        if (_currentDetector == detector) {
          _currentDetector = null;
        }
      }
    }
  }

  // 执行HTTP请求，处理超时和取消
  Future<Response<dynamic>?> _safeHttpRequest(String url, {Options? options}) async {
    if (_isCancelled()) return null;
    
    final requestOptions = options ?? _defaultOptions;
    
    try {
      return await _httpUtil.getRequestWithResponse(
        url,
        options: requestOptions,
        cancelToken: cancelToken,
      ).timeout(timeoutDuration);
    } catch (e, stackTrace) {
      if (_isCancelled()) {
        LogUtil.i('HTTP请求取消: $url');
        return null;
      }
      if (e is DioException) {
        LogUtil.e('HTTP请求失败: ${e.message}, URL: $url');
      } else if (e is TimeoutException) {
        LogUtil.e('HTTP请求超时(${timeoutDuration.inSeconds}秒): $url');
      } else {
        LogUtil.logError('HTTP请求错误', e, stackTrace);
      }
      return null;
    }
  }

  // 获取YouTube普通视频流URL
  Future<String> _getYouTubeVideoUrl() async {
    if (_isCancelled()) return ERROR_RESULT;
    try {
      var video = await yt.videos.get(url);
      if (_isCancelled()) return ERROR_RESULT;
      var manifest = await yt.videos.streams.getManifest(video.id);
      if (_isCancelled()) return ERROR_RESULT;
      LogUtil.i('HLS流: ${manifest.hls.length}, 混合流: ${manifest.muxed.length}');
      final hlsResult = await _processHlsStreams(manifest);
      if (hlsResult != ERROR_RESULT) return hlsResult;
      return _processMuxedStreams(manifest);
    } catch (e, stackTrace) {
      return _handleError('获取视频流失败', e, stackTrace);
    }
  }

  // 处理HLS流
  Future<String> _processHlsStreams(StreamManifest manifest) async {
    if (_isCancelled() || manifest.hls.isEmpty) {
      LogUtil.i('无HLS流或任务取消');
      return ERROR_RESULT;
    }
    try {
      final validStreams = manifest.hls
          .whereType<HlsVideoStreamInfo>()
          .where((s) => _isValidUrl(s.url.toString()) && s.container.name.toLowerCase() == 'm3u8')
          .toList();
      if (validStreams.isEmpty) {
        LogUtil.i('无有效HLS视频流');
        return ERROR_RESULT;
      }
      final streamResults = await Future.wait([
        _selectBestVideoStream(validStreams),
        _selectBestAudioStream(manifest),
      ]);
      final selectedVideoStream = streamResults[0] as HlsVideoStreamInfo?;
      final audioUrl = streamResults[1] as String?;
      if (selectedVideoStream != null && audioUrl != null) {
        final result = await _generateM3u8File(selectedVideoStream, audioUrl);
        if (result != ERROR_RESULT) return result;
      }
      LogUtil.i('HLS流处理失败');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      return _handleError('处理HLS流失败', e, stackTrace);
    }
  }

  // 选择最佳视频流
  Future<HlsVideoStreamInfo?> _selectBestVideoStream(List<HlsVideoStreamInfo> validStreams) async {
    if (_isCancelled() || validStreams.isEmpty) return null;
    for (final res in resolutionMap.keys) {
      final matchingStreams = validStreams.where((s) => s.qualityLabel.contains('${res}p')).toList();
      if (matchingStreams.isNotEmpty) {
        final selectedStream = matchingStreams.firstWhere(
          (s) => s.codec.toString().toLowerCase().contains('avc1'),
          orElse: () => matchingStreams.first,
        );
        if (selectedStream != null) {
          LogUtil.i('找到${res}p视频流, 码率: ${selectedStream.bitrate.kiloBitsPerSecond}Kbps');
          return selectedStream;
        }
      }
    }
    LogUtil.i('无符合条件的视频流');
    return null;
  }

  // 选择最佳音频流
  Future<String?> _selectBestAudioStream(StreamManifest manifest) async {
    if (_isCancelled()) return null;
    try {
      final audioStreams = manifest.hls
          .whereType<HlsAudioStreamInfo>()
          .where((s) => _isValidUrl(s.url.toString()) && s.container.name.toLowerCase() == 'm3u8')
          .toList();
      if (audioStreams.isEmpty) {
        LogUtil.i('无有效HLS音频流');
        return null;
      }
      final audioStream = audioStreams.firstWhere(
        (s) => (s.bitrate.bitsPerSecond - 128000).abs() < 10000,
        orElse: () => audioStreams.first,
      );
      LogUtil.i('找到音频流, 码率: ${audioStream.bitrate.kiloBitsPerSecond}Kbps');
      return audioStream.url.toString();
    } catch (e, stackTrace) {
      LogUtil.logError('选择音频流失败', e, stackTrace);
      return null;
    }
  }

  // 处理混合流
  String _processMuxedStreams(StreamManifest manifest) {
    if (_isCancelled()) return ERROR_RESULT;
    try {
      final streamInfo = _getBestMuxedStream(manifest);
      if (streamInfo != null && _isValidUrl(streamInfo.url.toString())) {
        LogUtil.i('找到${streamInfo.container.name}混合流');
        return streamInfo.url.toString();
      }
      LogUtil.e('无有效混合流');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      return _handleError('处理混合流失败', e, stackTrace);
    }
  }

  // 生成并保存M3U8文件
  Future<String> _generateM3u8File(HlsVideoStreamInfo videoStream, String audioUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/master_youtube.m3u8';
      final codecMatch = RegExp(r'codecs="([^"]+)"').firstMatch(videoStream.codec.toString());
      final codecs = codecMatch?.group(1) ?? 'avc1.4D401F,mp4a.40.2';
      final resolution = videoStream.videoResolution;
      final combinedM3u8 = '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=${videoStream.bitrate.bitsPerSecond},'
          'RESOLUTION=${resolution.width}x${resolution.height},'
          'CODECS="$codecs",'
          'AUDIO="audio_group"\n'
          '${videoStream.url}\n'
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_group",NAME="Audio",'
          'DEFAULT=YES,AUTOSELECT=YES,URI="$audioUrl"';
      await File(filePath).writeAsString(combinedM3u8);
      LogUtil.i('保存m3u8文件: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      return _handleError('保存m3u8文件失败', e, stackTrace);
    }
  }

  // 获取最佳混合流，优先MP4
  StreamInfo? _getBestMuxedStream(StreamManifest manifest) {
    if (manifest.muxed.isEmpty) {
      LogUtil.i('无混合流');
      return null;
    }
    try {
      final validStreams = manifest.muxed.where((s) => _isValidUrl(s.url.toString())).toList();
      if (validStreams.isEmpty) {
        LogUtil.i('无有效混合流');
        return null;
      }
      final streamInfo = validStreams.firstWhere(
        (s) => s.container.name.toLowerCase() == 'mp4',
        orElse: () => validStreams.first,
      );
      return streamInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('选择混合流失败', e, stackTrace);
      return null;
    }
  }

  // 获取YouTube直播流URL
  Future<String> _getYouTubeLiveStreamUrl() async {
    if (_isCancelled()) return ERROR_RESULT;
    try {
      final m3u8Url = await _getYouTubeM3U8Url(url, resolutionMap.keys.toList());
      if (m3u8Url != null) {
        LogUtil.i('获取直播流: $m3u8Url');
        return m3u8Url;
      }
      LogUtil.i('无有效直播流');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      if (!_isCancelled()) {
        return _handleError('获取直播流失败', e, stackTrace);
      }
      return ERROR_RESULT;
    }
  }

  // 从网页提取HLS清单URL
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isCancelled()) return null;
    LogUtil.i('获取HLS清单: $youtubeUrl');
    final response = await _safeHttpRequest(youtubeUrl);
    if (response == null || _isCancelled()) return null;
    if (response.statusCode == 200) {
      return await _extractAndProcessHlsManifest(response.data.toString(), preferredQualities);
    }
    LogUtil.e('HTTP请求失败，状态码: ${response.statusCode}');
    return null;
  }

  // 提取并处理HLS清单
  Future<String?> _extractAndProcessHlsManifest(String responseData, List<String> preferredQualities) async {
    if (_isCancelled()) return null;
    const styleEndMarker = '</style>';
    int lastStyleEnd = responseData.lastIndexOf(styleEndMarker);
    if (lastStyleEnd != -1) {
      responseData = responseData.substring(lastStyleEnd + styleEndMarker.length);
    }
    final match = hlsManifestRegex.firstMatch(responseData);
    if (match == null || match.groupCount < 1 || match.group(1) == null) {
      LogUtil.i('无hlsManifestUrl');
      return null;
    }
    final indexM3u8Url = match.group(1)!;
    if (!indexM3u8Url.endsWith('.m3u8')) {
      LogUtil.i('hlsManifestUrl无效');
      return null;
    }
    final qualityUrl = await _getQualityM3U8Url(indexM3u8Url, preferredQualities);
    if (qualityUrl != null) {
      return qualityUrl;
    }
    LogUtil.i('无有效质量流');
    return null;
  }

  // 从M3U8清单选择指定质量流
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isCancelled()) return null;
    LogUtil.i('解析HLS清单: $indexM3u8Url');
    final response = await _safeHttpRequest(indexM3u8Url);
    if (response == null || _isCancelled()) return null;
    if (response.statusCode != 200) {
      LogUtil.e('HLS清单请求失败，状态码: ${response.statusCode}');
      return null;
    }
    return _parseM3u8AndSelectQuality(response.data.toString(), preferredQualities);
  }

  // 解析M3U8清单并选择最佳质量
  String? _parseM3u8AndSelectQuality(String responseData, List<String> preferredQualities) {
    if (_isCancelled()) return null;
    final lines = responseData.split('\n');
    final qualityUrls = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      if (extStreamInfRegex.hasMatch(lines[i])) {
        final quality = _extractQuality(lines[i]);
        if (quality != null && i + 1 < lines.length) {
          qualityUrls[quality] = lines[i + 1].trim();
        }
      }
      if (_isCancelled()) return null;
    }
    for (var quality in preferredQualities) {
      if (qualityUrls.containsKey(quality)) {
        LogUtil.i('选择${quality}p流: ${qualityUrls[quality]}');
        return qualityUrls[quality];
      }
    }
    if (qualityUrls.isNotEmpty) {
      final firstQuality = qualityUrls.keys.first;
      LogUtil.i('使用${firstQuality}p流: ${qualityUrls.values.first}');
      return qualityUrls.values.first;
    }
    LogUtil.i('无有效子流地址');
    return null;
  }

  // 提取M3U8清单行中的质量信息
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
}
