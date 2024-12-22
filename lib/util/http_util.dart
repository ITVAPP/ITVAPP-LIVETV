import 'dart:io';
import 'dart:async';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import '../generated/l10n.dart';

// 缓存条目类
class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  
  CacheEntry(this.data, this.timestamp);
}

// 缓存管理类
class CacheManager {
  static final _cache = <String, CacheEntry<dynamic>>{};
  
  static Future<T?> getCachedResponse<T>(String key, Duration maxAge) async {
    final entry = _cache[key];
    if (entry != null && DateTime.now().difference(entry.timestamp) < maxAge) {
      return entry.data as T?;
    }
    return null;
  }
  
  static void setCache<T>(String key, T data) {
    _cache[key] = CacheEntry<T>(data, DateTime.now());
  }
  
  static void clearCache() {
    _cache.clear();
  }
}

// HTTP错误处理类
class HttpError {
  final int code;
  final String message;
  final dynamic data;
  
  const HttpError({
    required this.code,
    required this.message,
    this.data,
  });
  
  static HttpError fromDioError(DioException error) {
    String errorMessage = formatError(error);
    return HttpError(
      code: error.response?.statusCode ?? -1,
      message: errorMessage,
      data: error.response?.data
    );
  }
}

// 自定义请求拦截器
class RequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 添加公共参数
    options.queryParameters['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    // 动态添加请求头
    options.headers.addAll(HeadersConfig.generateHeaders(url: options.path));
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!err.requestOptions.extra.containsKey('retry_count')) {
      err.requestOptions.extra['retry_count'] = 0;
    }
    super.onError(err, handler);
  }
}

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._internal();
  
  // 定义常量配置
  static const _defaultTimeout = Duration(seconds: 8);
  static const _defaultMaxRetries = 2;
  static const _defaultRetryDelay = Duration(seconds: 2);
  static const _maxCacheAge = Duration(minutes: 5);
  
  late final Dio _dio;
  bool _isDisposed = false;  // 资源释放标记
  
  // 配置参数
  final BaseOptions options;
  final CancelToken cancelToken;

  factory HttpUtil() {
    return _instance;
  }
  
  HttpUtil._internal() : 
    options = BaseOptions(
      connectTimeout: _defaultTimeout,
      receiveTimeout: _defaultTimeout,
      sendTimeout: _defaultTimeout,
      validateStatus: (int? status) => status != null && status < 500,
    ),
    cancelToken = CancelToken();
  
  // 初始化方法
  void initialize() {
    if (_isDisposed) return;
    
    _dio = Dio(options)
      ..interceptors.addAll([
        RequestInterceptor(),
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: false,
          responseHeader: false,
        ),
      ]);

    // HTTP客户端配置
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..maxConnectionsPerHost = 8
        ..connectionTimeout = const Duration(seconds: 10)
        ..idleTimeout = const Duration(seconds: 30)
        ..autoUncompress = true;
      return client;
    };
  }
  
  // 资源释放方法
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    cancelToken.cancel('HttpUtil disposed');
    _dio.close(force: true);
    CacheManager.clearCache();
  }
  
  // 计算重试延迟的方法
  Future<Duration> _getNextDelay(int attempt, Duration initial) async {
    final maxDelay = const Duration(minutes: 1);
    final delay = initial * (1 << attempt); // 指数增长
    return delay > maxDelay ? maxDelay : delay;
  }

  // GET请求方法
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress,
      int retryCount = _defaultMaxRetries,
      Duration retryDelay = _defaultRetryDelay,
      bool useCache = true}) async {
    
    if (_isDisposed) return null;
    
    // 检查缓存
    if (useCache) {
      final cachedData = await CacheManager.getCachedResponse<T>(
        path + (queryParameters?.toString() ?? ''),
        _maxCacheAge
      );
      if (cachedData != null) {
        LogUtil.i('使用缓存数据: $path');
        return cachedData;
      }
    }
    
    Response? response;
    int currentAttempt = 0;
    Duration currentDelay = retryDelay;

    while (currentAttempt < retryCount) {
      try {
        response = await _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: (options ?? Options()).copyWith(
            extra: {'attempt': currentAttempt},
            headers: HeadersConfig.generateHeaders(url: path),
          ),
          cancelToken: cancelToken ?? this.cancelToken,
          onReceiveProgress: onReceiveProgress,
        );

        if (response.data != null) {
          if (useCache) {
            CacheManager.setCache(
              path + (queryParameters?.toString() ?? ''),
              response.data
            );
          }
          return response.data;
        }
        return null;
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace);

        if (currentAttempt >= retryCount || 
            e.type == DioExceptionType.cancel ||
            _isDisposed) {
          formatError(e);
          return null;
        }

        currentDelay = await _getNextDelay(currentAttempt, retryDelay);
        LogUtil.i('等待 ${currentDelay.inSeconds} 秒后重试第 $currentAttempt 次');
        await Future.delayed(currentDelay);
      }
    }
    return null;
  }

  // 下载方法
  Future<(int?, String?)> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    if (_isDisposed) return (null, 'HttpUtil已释放');
    
    try {
      final headers = HeadersConfig.generateHeaders(url: url);

      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          progressCallback?.call(received / total);
        },
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          error: '状态码: ${response.statusCode}'
        );
      }

      LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
      return (response.statusCode, null);
    } on DioException catch (e, stackTrace) {
      final error = HttpError.fromDioError(e);
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return (500, error.message);
    }
  }
}

String formatError(DioException e) {
  String message = '';
  LogUtil.safeExecute(() {
    message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut,
      DioExceptionType.sendTimeout => S.current.netSendTimeout,
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout,
      DioExceptionType.badResponse => S.current.netBadResponse(
          e.response?.statusCode?.toString() ?? ''),
      DioExceptionType.cancel => S.current.netCancel,
      _ => e.message.toString()
    };
    LogUtil.v(message);
  }, '处理 DioException 错误时发生异常');
  return message;
}
