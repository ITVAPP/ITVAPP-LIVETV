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

  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  late final Dio _dio; // 使用 Dio 进行 HTTP 请求

  CancelToken cancelToken = CancelToken(); // 用于取消请求的全局令牌

  factory HttpUtil() => _instance;

  // 修改代码开始
  // 构造函数：初始化 Dio 配置，移除多余的 options 成员，添加证书验证选项
  HttpUtil._({bool ignoreBadCertificate = false}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: defaultConnectTimeoutSeconds), // 默认连接超时
      receiveTimeout: const Duration(seconds: defaultReceiveTimeoutSeconds), // 默认接收超时
      responseType: ResponseType.bytes, // 统一使用字节响应类型，避免重复设置
    ));

    // 自定义 HttpClient 适配器，限制最大连接数，默认不忽略证书验证
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..maxConnectionsPerHost = maxConnectionsPerHost
          ..autoUncompress = true
          ..badCertificateCallback = ignoreBadCertificate
              ? (X509Certificate cert, String host, int port) => true
              : null; // 默认不忽略证书错误
        return client;
      };
    }
  }
  // 修改代码结束

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

    // 处理 Brotli 压缩的内容
    if (contentEncoding.contains('br')) {
      try {
        final decodedBytes = brotliDecode(Uint8List.fromList(bytes));
        response.data = _decodeContent(decodedBytes, contentType); // 提取解码逻辑
        LogUtil.i('成功解码 Brotli 压缩内容');
      } catch (e, stackTrace) {
        LogUtil.logError('Brotli 解压缩失败', e, stackTrace);
        response.data = _decodeFallback(bytes, contentType); // 回退解码
      }
    } else {
      response.data = _decodeFallback(bytes, contentType); // 非 Brotli 内容解码
    }

    // 统一处理字符串 trim，避免重复代码
    if (response.data is String) {
      response.data = (response.data as String).trim();
    }
    return response;
  }

  // 修改代码开始
  // 提取空内容处理逻辑为独立函数，减少重复
  dynamic _handleEmptyContent(String contentType, {bool isJson = false}) {
    LogUtil.v('内容为空，返回默认值');
    if (isJson) {
      return contentType.contains('array') ? [] : {};
    }
    return '';
  }

  // 内容解码逻辑
  dynamic _decodeContent(List<int> bytes, String contentType) {
    if (bytes.isEmpty) {
      return _handleEmptyContent(contentType);
    }
    
    final text = utf8.decode(bytes, allowMalformed: true);
    if (contentType.contains('json')) {
      try {
        if (text.isEmpty) {
          return _handleEmptyContent(contentType, isJson: true);
        }
        return jsonDecode(text);
      } catch (e) {
        LogUtil.e('JSON 解析失败: $e');
        return text;
      }
    }
    return text;
  }

  // 回退解码逻辑，处理非 Brotli 或解压失败的情况
  dynamic _decodeFallback(List<int> bytes, String contentType) {
    if (bytes.isEmpty) {
      return _handleEmptyContent(contentType);
    }
    
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (contentType.contains('json')) {
        try {
          if (text.isEmpty) {
            return _handleEmptyContent(contentType, isJson: true);
          }
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
        return latin1.decode(bytes);
      } catch (e) {
        LogUtil.e('所有解码尝试均失败: $e');
        return bytes; // 保留原始字节数据
      }
    }
  }

  // 优化类型转换逻辑，简化代码
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null;
    
    if (data is List && data.isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空数组');
      return null;
    }
    
    if (data is String) {
      data = data.trim();
      if (data.isEmpty) {
        LogUtil.v('_parseResponseData: 数据为空字符串');
        return null;
      }
    }

    if (parseData != null) {
      try {
        return parseData(data);
      } catch (e, stackTrace) {
        LogUtil.logError('自定义解析失败: $data', e, stackTrace);
        return null;
      }
    }

    if (T == String) {
      if (data is String) return data as T;
      if (data is Map || data is List) return jsonEncode(data) as T;
      if (data is num || data is bool) return data.toString() as T;
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})');
      return null;
    }

    return data is T ? data : null; // 直接使用类型检查
  }
  // 修改代码结束

  // 修改代码开始
  // 合并 GET 和 POST 请求逻辑，优化超时处理并添加详细注释
  Future<R?> _performRequest<R>({
    required bool isPost, // 使用布尔值区分请求类型
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
    Response? response;
    int currentAttempt = 0;

    options = options ?? Options();

    while (currentAttempt < retryCount) {
      try {
        // 获取请求头，优先使用 options.headers
        final headers = options.headers?.isNotEmpty == true
            ? options.headers!
            : HeadersConfig.generateHeaders(url: path);

        // 获取超时设置，避免修改全局 _dio.options
        final connectTimeout = _getTimeout(
          options.extra?['connectTimeout'] as Duration?,
          _dio.options.connectTimeout,
        );
        final receiveTimeout = _getTimeout(
          options.extra?['receiveTimeout'] as Duration?,
          _dio.options.receiveTimeout,
        );

        // 配置局部请求选项，包含超时和头信息
        final requestOptions = options.copyWith(
          headers: headers,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        );

        // 执行 HTTP 请求，根据 isPost 区分 GET 或 POST
        response = await (isPost
            ? _dio.post(
                path,
                data: data,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: cancelToken ?? this.cancelToken,
                onSendProgress: onSendProgress,
                onReceiveProgress: onReceiveProgress,
              )
            : _dio.get(
                path,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: cancelToken ?? this.cancelToken,
                onReceiveProgress: onReceiveProgress,
              ));

        // 处理响应，包括解压缩和类型转换
        response = _processResponse(response);
        return onSuccess(response);
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

        // 重试前等待指定延迟时间
        await Future.delayed(retryDelay);
        LogUtil.i('等待 ${retryDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
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
  // 修改代码结束

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
          receiveTimeout: const Duration(seconds: downloadReceiveTimeoutSeconds),
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) progressCallback?.call(received / total);
        },
      );

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
