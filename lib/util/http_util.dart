import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:brotli/brotli.dart';
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class HttpUtil {
  // 常量定义
  static const int defaultConnectTimeoutSeconds = 3; // 默认连接超时时间（秒）
  static const int defaultReceiveTimeoutSeconds = 9; // 默认接收超时时间（秒）
  static const int maxConnectionsPerHost = 5; // 每个主机的最大连接数
  static const int defaultRetryCount = 2; // 默认重试次数
  static const int defaultRetryDelaySeconds = 1; // 默认重试延迟时间（秒）
  static const int downloadReceiveTimeoutSeconds = 298; // 文件下载的接收超时时间（秒）
  static const int defaultFallbackStatusCode = 500; // 下载失败时的默认状态码
  static const int successStatusCode = 200; // 成功的状态码
  static const bool defaultIgnoreBadCertificate = true; // 默认是否忽略不安全证书，false 表示不忽略

  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  late final Dio _dio; // 使用 Dio 进行 HTTP 请求

  CancelToken cancelToken = CancelToken(); // 用于取消请求的全局令牌（将被优化为按请求分配）

  factory HttpUtil() => _instance;

  // 构造函数：初始化 Dio 配置，支持通过参数覆盖默认的证书验证设置
  HttpUtil._({bool? ignoreBadCertificate}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: defaultConnectTimeoutSeconds), // 默认连接超时
      receiveTimeout: const Duration(seconds: defaultReceiveTimeoutSeconds), // 默认接收超时
      responseType: ResponseType.bytes, // 统一使用字节响应类型，避免重复设置
    ));

    // 自定义 HttpClient 适配器，限制最大连接数，使用常量控制默认证书验证行为
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..maxConnectionsPerHost = maxConnectionsPerHost
          ..autoUncompress = true
          ..badCertificateCallback = (ignoreBadCertificate ?? defaultIgnoreBadCertificate)
              ? (X509Certificate cert, String host, int port) => true
              : null; // 根据参数或常量决定是否忽略证书错误
        return client;
      };
    }

    // 添加拦截器以动态调整超时设置
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final connectTimeout = _getTimeout(
          options.extra['connectTimeout'] as Duration?,
          _dio.options.connectTimeout,
        );
        final receiveTimeout = _getTimeout(
          options.extra['receiveTimeout'] as Duration?,
          _dio.options.receiveTimeout,
        );
        options.connectTimeout = connectTimeout;
        options.receiveTimeout = receiveTimeout;
        handler.next(options);
      },
    ));
  }

  // 添加 dispose 方法以清理资源
  void dispose() {
    cancelToken.cancel('HttpUtil disposed');
    _dio.close();
    LogUtil.i('HttpUtil 已释放资源');
  }

  // 超时设置的工具函数
  Duration _getTimeout(Duration? customTimeout, Duration? defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout ?? const Duration(seconds: defaultConnectTimeoutSeconds); // 提供最终默认值
  }

  Response _processResponse(Response response) {
    // 如果响应数据不是字节数组，说明已经处理过，直接返回
    if (!(response.data is List<int>)) {
      return response;
    }

    final bytes = response.data as List<int>;
    
    // 添加空内容判断逻辑
    if (bytes.isEmpty) {
      LogUtil.v('响应内容为空字节数组，跳过解码处理');
      // 对于空内容，将其设置为空字符串，避免后续处理
      response.data = '';
      return response;
    }

    final contentEncoding = response.headers.value('content-encoding')?.toLowerCase() ?? '';
    final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';

    // 处理 Brotli 压缩或回退解码
    response.data = _decodeBytes(bytes, contentEncoding, contentType);

    // 统一处理字符串 trim，避免重复代码
    if (response.data is String) {
      response.data = (response.data as String).trim();
    }
    return response;
  }

  // 合并后的解码函数，处理 Brotli 和回退逻辑
  dynamic _decodeBytes(List<int> bytes, String contentEncoding, String contentType) {
    if (bytes.isEmpty) {
      LogUtil.v('内容为空，返回默认值');
      if (contentType.contains('json')) {
        return contentType.contains('array') ? [] : {};
      }
      return '';
    }

    List<int> decodedBytes = bytes;
    if (contentEncoding.contains('br')) {
      try {
        decodedBytes = brotliDecode(Uint8List.fromList(bytes));
        LogUtil.i('成功解码 Brotli 压缩内容');
      } catch (e, stackTrace) {
        LogUtil.logError('Brotli 解压缩失败', e, stackTrace);
        decodedBytes = bytes; // 解压失败时使用原始字节
      }
    }

    try {
      final text = utf8.decode(decodedBytes, allowMalformed: true);
      if (contentType.contains('json')) {
        if (text.isEmpty) {
          return contentType.contains('array') ? [] : {};
        }
        try {
          return jsonDecode(text);
        } catch (e) {
          LogUtil.e('JSON 解析失败: $e');
          return text;
        }
      }
      return text;
    } catch (e) {
      LogUtil.e('UTF-8 解码失败，尝试其他编码: $e');
      try {
        return latin1.decode(decodedBytes);
      } catch (e) {
        LogUtil.e('所有解码尝试均失败: $e');
        return decodedBytes; // 保留原始字节数据
      }
    }
  }

  // 优化后的类型转换逻辑
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null;

    // 提前处理常见类型，减少不必要检查
    if (T == String && data is String) return data.trim() as T;
    if (data is List && data.isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空数组');
      return null;
    }
    if (data is String && data.trim().isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空字符串');
      return null;
    }

    // 自定义解析优先执行
    if (parseData != null) {
      try {
        return parseData(data);
      } catch (e, stackTrace) {
        LogUtil.logError('自定义解析失败: $data', e, stackTrace);
        return null;
      }
    }

    // 处理特定类型转换
    if (T == String) {
      if (data is Map || data is List) return jsonEncode(data) as T;
      if (data is num || data is bool) return data.toString() as T;
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})');
      return null;
    }

    return data is T ? data : null; // 直接类型检查
  }

  // 提取重试逻辑为独立函数
  Future<R?> _retryRequest<R extends Response<dynamic>>({
    required Future<R?> Function() request,
    required String path,
    required bool isPost,
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
  }) async {
    Response? response;
    int currentAttempt = 0;

    while (currentAttempt < retryCount) {
      try {
        response = await request();
        return response as R?;
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError(
          '第 $currentAttempt 次${isPost ? 'POST' : 'GET'} 请求失败: $path\n'
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

  // 合并 GET 和 POST 请求逻辑，使用拦截器动态调整超时
  Future<R?> _performRequest<R>({
    required bool isPost,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
    required R? Function(Response response) onSuccess,
  }) async {
    options = options ?? Options();
    final headers = options.headers?.isNotEmpty == true
        ? options.headers!
        : HeadersConfig.generateHeaders(url: path);

    // 为每个请求创建独立的 CancelToken，避免全局竞争
    final requestCancelToken = cancelToken ?? CancelToken();

    final requestOptions = Options(
      headers: headers,
      extra: {
        'connectTimeout': options.extra?['connectTimeout'] as Duration?,
        'receiveTimeout': options.extra?['receiveTimeout'] as Duration?,
      },
    );

    return _retryRequest<Response<dynamic>>(
      request: () async {
        return await (isPost
            ? _dio.post(
                path,
                data: data,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: requestCancelToken,
                onSendProgress: onSendProgress,
                onReceiveProgress: onReceiveProgress,
              )
            : _dio.get(
                path,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: requestCancelToken,
                onReceiveProgress: onReceiveProgress,
              ));
      },
      path: path,
      isPost: isPost,
      retryCount: retryCount,
      retryDelay: retryDelay,
    ).then((response) => response != null ? onSuccess(_processResponse(response)) : null);
  }

  // GET 请求方法，精简参数
  Future<T?> getRequest<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      isPost: false,
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
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
  }) async {
    return _performRequest<Response>(
      isPost: false,
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => response,
    );
  }

  // POST 请求方法，精简参数
  Future<T?> postRequest<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      isPost: true,
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
    int retryCount = defaultRetryCount,
    Duration retryDelay = const Duration(seconds: defaultRetryDelaySeconds),
  }) async {
    return _performRequest<Response>(
      isPost: true,
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => response,
    );
  }

  // 文件下载方法，添加节流机制
  Future<int?> downloadFile(
    String url,
    String savePath, {
    ValueChanged<double>? progressCallback,
  }) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      DateTime? lastUpdate;
      double lastProgress = 0.0;

      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: downloadReceiveTimeoutSeconds),
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0 || progressCallback == null) return;

          final progress = received / total;
          final now = DateTime.now();
          // 每 500ms 更新一次进度
          if (lastUpdate == null || now.difference(lastUpdate!).inMilliseconds >= 500) {
            progressCallback(progress);
            lastUpdate = now;
            lastProgress = progress;
          }
        },
      );

      // 确保最后一次进度更新为 1.0
      if (progressCallback != null && lastProgress < 1.0) {
        progressCallback(1.0);
      }

      if (response.statusCode != successStatusCode) {
        throw DioException(
          requestOptions: response.requestOptions,
          error: '状态码: ${response.statusCode}',
        );
      }

      LogUtil.i('文件下载成功: $url,保存路径: $savePath');
      return response.statusCode;
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return defaultFallbackStatusCode;
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
