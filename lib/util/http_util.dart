import 'dart:io';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  late final Dio _dio; // 使用 Dio 进行 HTTP 请求

  // 初始化 Dio 的基础配置，这里主要设置超时时间，headers 在具体请求时动态生成
  BaseOptions options = BaseOptions(
    connectTimeout: const Duration(seconds: 3), // 设置默认连接超时时间
    receiveTimeout: const Duration(seconds: 8), // 设置默认接收超时时间
  );

  CancelToken cancelToken = CancelToken(); // 用于取消请求的全局令牌

  factory HttpUtil() => _instance;

  HttpUtil._() {
    // 初始化 Dio 实例
    _dio = Dio(options);

    // 自定义 HttpClient 适配器，限制每个主机的最大连接数，允许不安全的证书
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..maxConnectionsPerHost = 5
          ..autoUncompress = true
          ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }
  }

  // 超时设置的工具函数
  Duration _getTimeout(Duration? customTimeout, Duration defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout;
  }

  // 提取类型处理的公共函数，减少重复逻辑
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null;

    // 如果数据是字符串，去除前后的空格和换行符
    if (data is String) data = data.trim();

    // 如果提供了自定义解析函数，优先使用
    if (parseData != null) {
      try {
        return parseData(data);
      } catch (e, stackTrace) {
        LogUtil.logError('自定义解析失败: $data', e, stackTrace);
        return null;
      }
    }

    // 处理 String 类型
    if (T == String) {
      if (data is String) return data as T;
      if (data is Map || data is List) return jsonEncode(data) as T;
      if (data is int || data is double || data is bool) return data.toString() as T;
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})');
      return null;
    }

    // 其他类型直接尝试转换
    try {
      return data is T ? data as T : null;
    } catch (e) {
      LogUtil.e('类型转换失败: $data 无法转换为 $T');
      return null;
    }
  }

  // 核心请求逻辑，处理 GET 和 POST 请求
  Future<R?> _performRequest<R>({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    required R? Function(Response response) onSuccess,
  }) async {
    Response? response;
    int currentAttempt = 0;
    Map<String, String>? cachedHeaders; // 缓存第一次生成的 headers

    while (currentAttempt < retryCount) {
      try {
        // 生成或复用 headers
        final headers = cachedHeaders ??=
            currentAttempt == 0 ? HeadersConfig.generateHeaders(url: path) : {
                  'Content-Type': method.toUpperCase() == 'POST'
                      ? 'application/json'
                      : 'text/html'
                };

        // 提取超时设置
        final connectTimeout =
            _getTimeout(options?.extra?['connectTimeout'] as Duration?, options.connectTimeout);
        final receiveTimeout =
            _getTimeout(options?.extra?['receiveTimeout'] as Duration?, options.receiveTimeout);

        // 更新 Dio 配置，而不是创建新实例
        _dio.options
          ..connectTimeout = connectTimeout
          ..receiveTimeout = receiveTimeout
          ..headers = headers;

        // 执行请求，使用全局 cancelToken 或传入的 cancelToken
        response = await (method.toUpperCase() == 'POST'
            ? _dio.post(
                path,
                data: data,
                queryParameters: queryParameters,
                options: options,
                cancelToken: cancelToken ?? this.cancelToken,
                onSendProgress: onSendProgress,
                onReceiveProgress: onReceiveProgress,
              )
            : _dio.get(
                path,
                queryParameters: queryParameters,
                options: options,
                cancelToken: cancelToken ?? this.cancelToken,
                onReceiveProgress: onReceiveProgress,
              ));

        return onSuccess(response);
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError(
          '第 $currentAttempt 次 $method 请求失败: $path\n'
          '响应状态码: ${e.response?.statusCode}\n'
          '响应数据: ${e.response?.data}\n'
          '响应头: ${e.response?.headers}',
          e,
          stackTrace,
        );

        if (currentAttempt >= retryCount || e.type == DioExceptionType.cancel) {
          formatError(e);
          return null;
        }

        await Future.delayed(retryDelay);
        LogUtil.i('等待 ${retryDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
  }

  // GET 请求方法
  Future<T?> getRequest<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // GET 请求方法，返回完整 Response
  Future<Response?> getRequestWithResponse(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) {
        if (response.data is String) response.data = response.data.trim();
        return response;
      },
    );
  }

  // POST 请求方法
  Future<T?> postRequest<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      method: 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // POST 请求方法，返回完整 Response
  Future<Response?> postRequestWithResponse(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      method: 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) {
        if (response.data is String) response.data = response.data.trim();
        return response;
      },
    );
  }

  // 文件下载方法
  Future<int?> downloadFile(
    String url,
    String savePath, {
    ValueChanged<double>? progressCallback,
  }) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 298),
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) progressCallback?.call(received / total);
        },
      );

      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          error: '状态码: ${response.statusCode}',
        );
      }

      LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
      return response.statusCode;
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500;
    }
  }
}

// 统一处理 Dio 请求的异常
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut,
      DioExceptionType.sendTimeout => S.current.netSendTimeout,
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout,
      DioExceptionType.badResponse => S.current.netBadResponse(e.response?.statusCode ?? ''),
      DioExceptionType.cancel => S.current.netCancel,
      _ => e.message.toString()
    };
    LogUtil.v(message);
  }, '处理 DioException 错误时发生异常');
}
