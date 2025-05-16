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
  late final String url; // 流媒体URL
  final YoutubeExplode yt = YoutubeExplode(); // YouTube解析实例
  final HttpUtil _httpUtil = HttpUtil(); // HTTP工具单例
  Completer<void>? _completer; // 异步任务完成器
  final Duration timeoutDuration; // 任务超时时间
  late final CancelToken _cancelToken; // HTTP请求取消令牌
  bool _isDisposing = false; // 是否正在释放资源
  bool _isDisposed = false; // 是否已释放资源

  static GetM3U8? _currentDetector; // 当前GetM3U8实例
  static final Map<String, (String, DateTime)> _urlCache = {}; // URL缓存
  static bool _cleanupScheduled = false; // 缓存清理标志
  static final Object _cacheLock = Object(); // 缓存同步锁
  static const int _MAX_CACHE_ENTRIES = 100; // 缓存最大条目数
  static const int _CACHE_EXPIRY_MINUTES = 5; // 缓存有效期（分钟）

  static final Map<String, dynamic> _defaultOptionsExtra = {
    'connectTimeout': CONNECT_TIMEOUT,
    'receiveTimeout': RECEIVE_TIMEOUT,
  }; // 默认HTTP选项

  static const String ERROR_RESULT = 'ERROR'; // 错误结果常量
  static const Duration DEFAULT_TIMEOUT = Duration(seconds: 30); // 默认任务超时
  static const Duration CONNECT_TIMEOUT = Duration(seconds: 5); // HTTP连接超时
  static const Duration RECEIVE_TIMEOUT = Duration(seconds: 12); // HTTP接收超时
  static const Duration RETRY_DELAY = Duration(seconds: 1); // 重试延迟

  static const Map<String, (int, int)> resolutionMap = {
    '720': (1280, 720),
    '1080': (1920, 1080),
    '480': (854, 480),
    '360': (640, 360)
  }; // 视频分辨率映射

  static String rulesString = '.php@.asp@.jsp@.aspx'; // 重定向规则
  static const Set<String> validContainers = {'mp4', 'webm'}; // 有效容器格式

  static final RegExp hlsManifestRegex = RegExp(r'"hlsManifestUrl":"(https://[^"]+.m3u8)"'); // HLS清单正则
  static final RegExp resolutionRegex = RegExp(r'RESOLUTION=\d+x(\d+)'); // 分辨率正则
  static final RegExp extStreamInfRegex = RegExp(r'#EXT-X-STREAM-INF'); // M3U8流信息正则

  // 初始化StreamUrl实例，规范化输入URL，添加cancelToken参数
StreamUrl(String inputUrl, {
  Duration timeoutDuration = DEFAULT_TIMEOUT,
}) : timeoutDuration = timeoutDuration {
  url = inputUrl.contains('\$') ? inputUrl.split('\$')[0].trim() : inputUrl;
  // 始终创建新的CancelToken，确保生命周期正确
  _cancelToken = CancelToken();
  _ensureCacheCleanup();
}

  // 规范化URL，确保一致性
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

  // 启动缓存清理定时器
  static void _ensureCacheCleanup() {
    bool shouldSchedule = false;
    synchronized(() {
      shouldSchedule = !_cleanupScheduled;
      if (shouldSchedule) _cleanupScheduled = true;
    });
    if (shouldSchedule) {
      Timer.periodic(Duration(minutes: _CACHE_EXPIRY_MINUTES), (_) => _cleanCache());
    }
  }

  // 同步执行临界区代码
  static void synchronized(Function() action) => action();

  // 清理过期或过多缓存
  static void _cleanCache() {
    final now = DateTime.now();
    _urlCache.removeWhere((_, value) => now.difference(value.$2).inMinutes > _CACHE_EXPIRY_MINUTES);
    if (_urlCache.length > _MAX_CACHE_ENTRIES) {
      final sortedEntries = _urlCache.entries.toList()
        ..sort((a, b) => a.value.$2.compareTo(b.value.$2));
      final entriesToRemove = sortedEntries.take(_urlCache.length - _MAX_CACHE_ENTRIES ~/ 2);
      for (var entry in entriesToRemove) {
        _urlCache.remove(entry.key);
      }
    }
  }

  // 检查请求是否取消
  bool _isCancelled() => _cancelToken.isCancelled;

  // 获取流媒体URL，支持多种类型
  Future<String> getStreamUrl() async {
    // 检查取消状态
    if (_isCancelled() || _isDisposed) {
      LogUtil.i('任务已取消或已释放资源，返回ERROR');
      return ERROR_RESULT;
    }

    _completer = Completer<void>();
    final normalizedUrl = _normalizeUrl(url);
    if (_urlCache.containsKey(normalizedUrl)) {
      final (cachedResult, timestamp) = _urlCache[normalizedUrl]!;
      if (DateTime.now().difference(timestamp).inMinutes < _CACHE_EXPIRY_MINUTES &&
          cachedResult != ERROR_RESULT) {
        LogUtil.i('使用缓存的URL结果: $url');
        return cachedResult;
      }
    }
    try {
      String result;
      // 各处理逻辑前添加取消检查
      if (_isCancelled() || _isDisposed) {
        LogUtil.i('处理前检测到取消，返回ERROR');
        return ERROR_RESULT;
      }

      if (isGetM3U8Url(url)) {
        result = await _handleGetM3U8Url(url);
      } else if (isLZUrl(url)) {
        result = isILanzouUrl(url)
            ? 'https://lz.qaiu.top/parser?url=$url'
            : await LanzouParser.getLanzouUrl(url, cancelToken: _cancelToken);
      } else if (isYTUrl(url)) {
        final task = url.contains('ytlive') ? _getYouTubeLiveStreamUrl : _getYouTubeVideoUrl;
        result = await _retryTask(task);
      } else {
        result = url;
      }

      // 检查任务是否在处理过程中被取消
      if (_isCancelled() || _isDisposed) {
        LogUtil.i('处理后检测到取消，返回ERROR');
        return ERROR_RESULT;
      }

      if (result != ERROR_RESULT) {
        _urlCache[normalizedUrl] = (result, DateTime.now());
      }
      return result;
    } catch (e, stackTrace) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        LogUtil.i('解析任务被取消');
      } else {
        LogUtil.logError('获取视频流地址时发生错误', e, stackTrace);
      }
      return ERROR_RESULT;
    } finally {
      _completeSafely();
    }
  }

  // 重试任务，最多尝试两次
  Future<String> _retryTask(Future<String> Function() task) async {
    try {
      // 检查取消状态
      if (_isCancelled() || _isDisposed) {
        return ERROR_RESULT;
      }

      final result = await task().timeout(timeoutDuration);
      if (result != ERROR_RESULT) return result;
      LogUtil.e('首次获取视频流失败，准备重试');
    } catch (e) {
      if (_isCancelled() || _isDisposed) {
        LogUtil.i('首次任务被取消，不进行重试');
        return ERROR_RESULT;
      }
      LogUtil.e('首次获取视频流失败: ${e.toString()}，准备重试');
    }
    
    // 再次检查取消状态
    if (_isCancelled() || _isDisposed) {
      LogUtil.i('重试前任务已取消，直接返回');
      return ERROR_RESULT;
    }
    await Future.delayed(RETRY_DELAY);
    try {
      final result = await task().timeout(timeoutDuration);
      return result != ERROR_RESULT ? result : ERROR_RESULT;
    } catch (retryError) {
      if (_isCancelled() || _isDisposed) {
        LogUtil.i('重试任务被取消');
        return ERROR_RESULT;
      }
      LogUtil.e('重试获取视频流失败: ${retryError.toString()}');
      return ERROR_RESULT;
    }
  }

  // 安全完成Completer
  void _completeSafely() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  // 释放资源，取消未完成请求
  Future<void> dispose() async {
    // 防止重复调用
    if (_isDisposing || _isDisposed) {
      LogUtil.i('StreamUrl已在释放中或已释放，跳过dispose');
      return;
    }
    _isDisposing = true;
    
    LogUtil.i('开始释放StreamUrl资源: $url');
    
    try {
      if (!_cancelToken.isCancelled) {
        _cancelToken.cancel('StreamUrl disposed');
        LogUtil.i('已取消所有未完成的 HTTP 请求');
      }
      
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.completeError('资源已释放，任务被取消');
      }
      
      // 确保GetM3U8实例释放
      if (_currentDetector != null) {
        await _currentDetector?.dispose();
        _currentDetector = null;
      }
      
      try {
        yt.close();
      } catch (e, stackTrace) {
        LogUtil.logError('释放 YT 实例时发生错误', e, stackTrace);
      }
      
      // 尝试等待Completer完成
      try {
        if (_completer != null && !_completer!.isCompleted) {
          await _completer?.future.timeout(
            Duration(milliseconds: 300),
            onTimeout: () => LogUtil.i('等待_completer超时')
          );
        }
      } catch (e) {
        // 忽略超时或取消异常
      }
    } catch (e, stackTrace) {
      LogUtil.logError('StreamUrl释放资源时出错', e, stackTrace);
    } finally {
      _isDisposed = true;
      _isDisposing = false;
      LogUtil.i('StreamUrl资源释放完成: $url');
    }
  }

  // 判断是否为GetM3U8 URL
  bool isGetM3U8Url(String url) => url.toLowerCase().contains('getm3u8');

  // 判断是否为蓝奏云链接
  bool isLZUrl(String url) => !url.contains('|') && url.contains('lanzou');

  // 判断是否为ilanzou.com链接
  bool isILanzouUrl(String url) => url.toLowerCase().contains('ilanzou.com');

  // 判断是否为YouTube链接
  bool isYTUrl(String url) =>
      url.contains('youtube') || url.contains('youtu.be') || url.contains('googlevideo');

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
    if (_isCancelled() || _isDisposed) return ERROR_RESULT;
    await _currentDetector?.dispose();
    _currentDetector = null;
    GetM3U8? detector;
    try {
      detector = GetM3U8(
        url: url,
        timeoutSeconds: timeoutDuration.inSeconds,
        cancelToken: _cancelToken,
      );
      _currentDetector = detector;
      final result = await detector.getUrl();
      if (result.isEmpty) {
        LogUtil.e('GetM3U8返回空结果');
        return ERROR_RESULT;
      }
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('GetM3U8处理失败', e, stackTrace);
      return ERROR_RESULT;
    } finally {
      if (detector != null && detector == _currentDetector) {
        await detector.dispose();
        if (_currentDetector == detector) {
          _currentDetector = null;
        }
      }
    }
  }

  // 统一处理HTTP请求
  Future<Response<dynamic>?> _safeHttpRequest(String url, {Options? options}) async {
    if (_isCancelled()) return null;
    final requestOptions = options ?? Options();
    requestOptions.extra ??= {};
    requestOptions.extra!.addAll(Map<String, dynamic>.from(_defaultOptionsExtra));
    try {
      return await _httpUtil.getRequestWithResponse(
        url,
        options: requestOptions,
        cancelToken: _cancelToken,
      ).timeout(timeoutDuration);
    } catch (e, stackTrace) {
      if (_isCancelled()) {
        LogUtil.i('HTTP请求已取消: $url');
        return null;
      }
      if (e is DioException) {
        LogUtil.e('HTTP请求失败: ${e.message}, URL: $url');
      } else if (e is TimeoutException) {
        LogUtil.e('HTTP请求超时: $url');
      } else {
        LogUtil.logError('HTTP请求时发生错误', e, stackTrace);
      }
      return null;
    }
  }

  // 获取YouTube普通视频流URL
  Future<String> _getYouTubeVideoUrl() async {
    if (_isCancelled()) return ERROR_RESULT;
    try {
      var video = await yt.videos.get(url);
      if (_isCancelled()) {
        LogUtil.i('解析视频信息后任务被取消');
        return ERROR_RESULT;
      }
      var manifest = await yt.videos.streams.getManifest(video.id);
      if (_isCancelled()) {
        LogUtil.i('解析流清单后任务被取消');
        return ERROR_RESULT;
      }
      _logStreamInfo(manifest);
      final hlsResult = await _processHlsStreams(manifest);
      if (hlsResult != ERROR_RESULT) return hlsResult;
      return _processMuxedStreams(manifest);
    } catch (e, stackTrace) {
      LogUtil.logError('获取视频流时发生错误', e, stackTrace);
      return ERROR_RESULT;
    }
  }

  // 记录流信息
  void _logStreamInfo(StreamManifest manifest) {
    LogUtil.i('''
======= Manifest 流信息 =======
HLS流数量: ${manifest.hls.length}
混合流数量: ${manifest.muxed.length} 
===============================''');
    LogUtil.i('manifest 的格式化信息: ${manifest.toString()}');
  }

  // 处理HLS流
  Future<String> _processHlsStreams(StreamManifest manifest) async {
    if (_isCancelled() || manifest.hls.isEmpty) {
      LogUtil.i('没有可用的 HLS 流或任务已取消');
      return ERROR_RESULT;
    }
    LogUtil.i('开始处理HLS流');
    try {
      final allVideoStreams = manifest.hls.whereType<HlsVideoStreamInfo>().toList();
      LogUtil.i('找到 ${allVideoStreams.length} 个HLS视频流');
      final validStreams = allVideoStreams
          .where((s) => _isValidUrl(s.url.toString()) && s.container.name.toLowerCase() == 'm3u8')
          .toList();
      if (validStreams.isEmpty) {
        LogUtil.i('未找到有效的HLS视频流');
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
      LogUtil.i('HLS流处理未成功');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      LogUtil.logError('处理HLS流时发生错误', e, stackTrace);
      return ERROR_RESULT;
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
          _logVideoStreamInfo(selectedStream, res);
          return selectedStream;
        }
      }
    }
    LogUtil.i('未找到符合条件的视频流');
    return null;
  }

  // 记录视频流信息
  void _logVideoStreamInfo(HlsVideoStreamInfo stream, String resolution) {
    LogUtil.i('''找到 ${resolution}p 质量的视频流
tag: ${stream.tag}
qualityLabel: ${stream.qualityLabel}
videoCodec: ${stream.videoCodec}
codec: ${stream.codec}
container: ${stream.container}
bitrate: ${stream.bitrate.kiloBitsPerSecond} Kbps
videoQuality: ${stream.videoQuality}
videoResolution: ${stream.videoResolution}
framerate: ${stream.framerate}fps
url: ${stream.url}''');
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
        LogUtil.i('未找到有效的HLS音频流');
        return null;
      }
      final audioStream = audioStreams.firstWhere(
        (s) => (s.bitrate.bitsPerSecond - 128000).abs() < 10000,
        orElse: () => audioStreams.first,
      );
      if (audioStream != null) {
        LogUtil.i('''找到 HLS音频流
bitrate: ${audioStream.bitrate.kiloBitsPerSecond} Kbps
codec: ${audioStream.codec}
container: ${audioStream.container}
tag: ${audioStream.tag}
url: ${audioStream.url}''');
        return audioStream.url.toString();
      }
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('选择音频流时发生错误', e, stackTrace);
      return null;
    }
  }

  // 处理混合流
  String _processMuxedStreams(StreamManifest manifest) {
    if (_isCancelled()) return ERROR_RESULT;
    try {
      final streamInfo = _getBestMuxedStream(manifest);
      if (streamInfo != null) {
        final streamUrl = streamInfo.url.toString();
        if (_isValidUrl(streamUrl)) return streamUrl;
      }
      LogUtil.e('未找到任何符合条件的流');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      LogUtil.logError('处理混合流时发生错误', e, stackTrace);
      return ERROR_RESULT;
    }
  }

  // 生成并保存M3U8文件
  Future<String> _generateM3u8File(HlsVideoStreamInfo videoStream, String audioUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'master_youtube.m3u8';
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      final codecMatch = RegExp(r'codecs="([^"]+)"').firstMatch(videoStream.codec.toString());
      final codecs = codecMatch?.group(1) ?? 'avc1.4D401F,mp4a.40.2';
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
      return ERROR_RESULT;
    }
  }

  // 获取最佳混合流，优先MP4格式
  StreamInfo? _getBestMuxedStream(StreamManifest manifest) {
    if (manifest.muxed.isEmpty) {
      LogUtil.i('没有可用的混合流');
      return null;
    }
    try {
      LogUtil.i('查找普通混合流');
      final validStreams = manifest.muxed.where((s) => _isValidUrl(s.url.toString())).toList();
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

  // 获取YouTube直播流URL
  Future<String> _getYouTubeLiveStreamUrl() async {
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取直播流');
      return ERROR_RESULT;
    }
    LogUtil.i('开始获取 YouTube 直播流，URL: $url');
    try {
      final m3u8Url = await _getYouTubeM3U8Url(url, resolutionMap.keys.toList());
      if (m3u8Url != null) {
        LogUtil.i('成功获取直播流地址: $m3u8Url');
        return m3u8Url;
      }
      LogUtil.e('未能获取到有效的直播流地址');
      return ERROR_RESULT;
    } catch (e, stackTrace) {
      if (!_isCancelled()) {
        LogUtil.logError('获取 YT 直播流地址时发生错误', e, stackTrace);
      }
      return ERROR_RESULT;
    }
  }

  // 从网页提取HLS清单URL
  Future<String?> _getYouTubeM3U8Url(String youtubeUrl, List<String> preferredQualities) async {
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取 M3U8 URL');
      return null;
    }
    LogUtil.i('开始获取 HLS 清单地址，URL: $youtubeUrl，发送 GET 请求获取直播页面内容');
    final response = await _safeHttpRequest(youtubeUrl);
    if (response == null || _isCancelled()) return null;
    LogUtil.i('收到响应，状态码: ${response.statusCode}');
    if (response.statusCode == 200) {
      return await _extractAndProcessHlsManifest(response.data.toString(), preferredQualities);
    } else {
      LogUtil.e('HTTP 请求失败，状态码: ${response.statusCode}');
      return null;
    }
  }

  // 提取并处理HLS清单
  Future<String?> _extractAndProcessHlsManifest(String responseData, List<String> preferredQualities) async {
    if (_isCancelled()) return null;
    LogUtil.i('开始解析页面内容以提取 hlsManifestUrl');
    const styleEndMarker = '</style>';
    int lastStyleEnd = responseData.lastIndexOf(styleEndMarker);
    if (lastStyleEnd != -1) {
      responseData = responseData.substring(lastStyleEnd + styleEndMarker.length);
      LogUtil.i('找到最后一个 </style>，从其后开始查找 hlsManifestUrl');
    } else {
      LogUtil.i('未找到 </style>，使用完整响应数据');
    }
    final match = hlsManifestRegex.firstMatch(responseData);
    if (match == null || match.groupCount < 1) {
      LogUtil.e('未在页面内容中匹配到 hlsManifestUrl');
      return null;
    }
    final indexM3u8Url = match.group(1);
    if (indexM3u8Url == null || !indexM3u8Url.endsWith('.m3u8')) {
      LogUtil.e('hlsManifestUrl 提取结果无效');
      return null;
    }
    LogUtil.i('成功提取 hlsManifestUrl: $indexM3u8Url，开始解析质量并选择直播流地址');
    final qualityUrl = await _getQualityM3U8Url(indexM3u8Url, preferredQualities);
    if (qualityUrl != null) {
      LogUtil.i('成功选择质量直播流地址: $qualityUrl');
      return qualityUrl;
    } else {
      LogUtil.e('未能从清单中选择有效的质量直播流地址');
      return null;
    }
  }

  // 从M3U8清单选择指定质量流
  Future<String?> _getQualityM3U8Url(String indexM3u8Url, List<String> preferredQualities) async {
    if (_isCancelled()) {
      LogUtil.i('对象已释放，无法获取质量 M3U8 URL');
      return null;
    }
    LogUtil.i('开始解析 HLS 清单以选择质量，URL: $indexM3u8Url，首选分辨率顺序: $preferredQualities');
    final response = await _safeHttpRequest(indexM3u8Url);
    if (response == null || _isCancelled()) return null;
    LogUtil.i('收到响应，状态码: ${response.statusCode}');
    if (response.statusCode != 200) {
      LogUtil.e('HTTP 请求失败，状态码: ${response.statusCode}');
      return null;
    }
    return _parseM3u8AndSelectQuality(response.data.toString(), preferredQualities);
  }

  // 解析M3U8清单并选择最佳质量
  String? _parseM3u8AndSelectQuality(String responseData, List<String> preferredQualities) {
    if (_isCancelled()) return null;
    LogUtil.i('开始解析 HLS 清单内容');
    final lines = responseData.split('\n');
    final length = lines.length;
    final qualityUrls = <String, String>{};
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
    for (var quality in preferredQualities) {
      if (qualityUrls.containsKey(quality)) {
        LogUtil.i('选择分辨率 ${quality}p 的流地址: ${qualityUrls[quality]}');
        return qualityUrls[quality];
      }
    }
    if (qualityUrls.isNotEmpty) {
      final firstQuality = qualityUrls.keys.first;
      LogUtil.i('未找到首选质量的直播流，使用 ${firstQuality}p，返回流地址: ${qualityUrls.values.first}');
      return qualityUrls.values.first;
    } else {
      LogUtil.e('HLS 清单中未找到任何有效的子流地址');
      return null;
    }
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

  // 检查URL是否需要重定向
  bool needsRedirectCheck(String url, String rulesString) {
    final rules = rulesString.split('@');
    return rules.any((rule) => url.toLowerCase().contains(rule.toLowerCase()));
  }
}
