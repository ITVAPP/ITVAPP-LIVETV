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
  static const bool defaultIgnoreBadCertificate = true; // 默认忽略不安全证书

  static final HttpUtil _instance = HttpUtil._(); // 单例模式，确保全局唯一实例
  late final Dio _dio; // Dio 实例，用于 HTTP 请求

  CancelToken cancelToken = CancelToken(); // 全局取消请求的令牌

  factory HttpUtil() => _instance; // 工厂方法，返回单例实例

  // 私有构造函数，初始化 Dio 配置
  HttpUtil._({bool? ignoreBadCertificate}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: defaultConnectTimeoutSeconds), // 设置连接超时
      receiveTimeout: const Duration(seconds: defaultReceiveTimeoutSeconds), // 设置接收超时
      responseType: ResponseType.bytes, // 默认响应类型为字节数组
    ));

    // 配置 HttpClient 适配器，设置最大连接数和证书验证
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..maxConnectionsPerHost = maxConnectionsPerHost // 限制主机连接数
          ..autoUncompress = true // 自动解压响应
          ..badCertificateCallback = (ignoreBadCertificate ?? defaultIgnoreBadCertificate)
              ? (X509Certificate cert, String host, int port) => true
              : null; // 根据参数决定是否忽略证书错误
        return client;
      };
    }

    // 添加拦截器，动态调整请求超时
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final connectTimeout = _getTimeout(
          options.extra['connectTimeout'] as Duration?,
          _dio.options.connectTimeout,
        ); // 获取连接超时
        final receiveTimeout = _getTimeout(
          options.extra['receiveTimeout'] as Duration?,
          _dio.options.receiveTimeout,
        ); // 获取接收超时
        options.connectTimeout = connectTimeout; // 应用连接超时
        options.receiveTimeout = receiveTimeout; // 应用接收超时
        handler.next(options); // 继续请求
      },
    ));
  }

  // 释放资源，清理 Dio 和取消令牌
  void dispose() {
    cancelToken.cancel('HttpUtil disposed'); // 取消所有请求
    _dio.close(); // 关闭 Dio 实例
    LogUtil.i('HttpUtil 已释放资源'); // 日志记录资源释放
  }

  // 获取超时值，优先使用自定义值
  Duration _getTimeout(Duration? customTimeout, Duration? defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout ?? const Duration(seconds: defaultConnectTimeoutSeconds); // 默认超时
  }

  // 处理响应数据，解码字节数组
  Response _processResponse(Response response) {
    if (!(response.data is List<int>)) return response; // 非字节数据直接返回
    final bytes = response.data as List<int>;
    if (bytes.isEmpty) {
      LogUtil.v('响应内容为空字节数组，跳过解码处理'); // 空字节日志
      response.data = ''; // 设置为空字符串
      return response;
    }
    
    // 获取编码类型和内容类型，支持不同大小写格式
    String contentEncoding = '';
    String contentType = '';
    
    // 尝试获取 content-encoding 头（支持不同大小写）
    for (var key in response.headers.map.keys) {
      if (key.toLowerCase() == 'content-encoding') {
        contentEncoding = response.headers.value(key)?.toLowerCase() ?? '';
        break;
      }
    }
    
    // 尝试获取 content-type 头（支持不同大小写）
    for (var key in response.headers.map.keys) {
      if (key.toLowerCase() == 'content-type') {
        contentType = response.headers.value(key)?.toLowerCase() ?? '';
        break;
      }
    }
    
    response.data = _decodeBytes(bytes, contentEncoding, contentType); // 解码字节数据
    if (response.data is String) response.data = (response.data as String).trim(); // 去除字符串首尾空格
    return response;
  }

  // 解码字节数据，支持 Brotli 和回退逻辑
  dynamic _decodeBytes(List<int> bytes, String contentEncoding, String contentType) {
    if (bytes.isEmpty) {
      LogUtil.v('内容为空，返回默认值'); // 空内容日志
      return contentType.contains('json') ? (contentType.contains('array') ? [] : {}) : '';
    }
    List<int> decodedBytes = bytes;
    if (contentEncoding.contains('br')) {
      try {
        decodedBytes = brotliDecode(Uint8List.fromList(bytes)); // 解码 Brotli 压缩
        LogUtil.i('成功解码 Brotli 压缩内容'); // 解码成功日志
      } catch (e, stackTrace) {
        LogUtil.logError('Brotli 解压缩失败', e, stackTrace); // 解码失败日志
        decodedBytes = bytes; // 使用原始字节
      }
    }
    try {
      final text = utf8.decode(decodedBytes, allowMalformed: true); // UTF-8 解码
      if (contentType.contains('json')) {
        if (text.isEmpty) return contentType.contains('array') ? [] : {}; // 空 JSON 处理
        try {
          return jsonDecode(text); // 解析 JSON
        } catch (e) {
          LogUtil.e('JSON 解析失败: $e'); // JSON 解析失败日志
          return text;
        }
      }
      return text;
    } catch (e) {
      LogUtil.e('UTF-8 解码失败，尝试其他编码: $e'); // UTF-8 失败日志
      try {
        return latin1.decode(decodedBytes); // 尝试 Latin1 解码
      } catch (e) {
        LogUtil.e('所有解码尝试均失败: $e'); // 解码完全失败日志
        return decodedBytes; // 返回原始字节
      }
    }
  }

  // 解析响应数据为指定类型
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null; // 数据为空返回 null
    if (T == String && data is String) return data.trim() as T; // 直接返回修剪后的字符串
    if (data is List && data.isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空数组'); // 空数组日志
      return null;
    }
    if (data is String && data.trim().isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空字符串'); // 空字符串日志
      return null;
    }
    if (parseData != null) {
      try {
        return parseData(data); // 执行自定义解析
      } catch (e, stackTrace) {
        LogUtil.logError('自定义解析失败: $data', e, stackTrace); // 自定义解析失败日志
        return null;
      }
    }
    if (T == String) {
      if (data is Map || data is List) return jsonEncode(data) as T; // 转换为 JSON 字符串
      if (data is num || data is bool) return data.toString() as T; // 转换为字符串
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})'); // 类型转换失败日志
      return null;
    }
    return data is T ? data : null; // 类型匹配则返回
  }

  // 执行重试请求逻辑
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
        response = await request(); // 执行请求
        return response as R?;
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError(
          '第 $currentAttempt 次${isPost ? 'POST' : 'GET'} 请求失败: $path\n'
          '响应状态码: ${e.response?.statusCode}\n',
          e,
          stackTrace,
        ); // 记录请求失败日志
        if (currentAttempt >= retryCount || e.type == DioExceptionType.cancel) {
          formatError(e); // 处理最终错误
          return null;
        }
        await Future.delayed(retryDelay); // 延迟重试
      }
    }
    return null;
  }

  // 统一执行 GET/POST 请求
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
    options = options ?? Options(); // 默认选项
    final headers = options.headers?.isNotEmpty == true
        ? options.headers!
        : HeadersConfig.generateHeaders(url: path); // 生成请求头
    final requestCancelToken = cancelToken ?? CancelToken(); // 每个请求独立取消令牌
    final requestOptions = Options(
      headers: headers,
      extra: {
        'connectTimeout': options.extra?['connectTimeout'] as Duration?,
        'receiveTimeout': options.extra?['receiveTimeout'] as Duration?,
      },
    ); // 配置请求选项
    return _retryRequest<Response<dynamic>>(
      request: () async => isPost
          ? _dio.post(path, data: data, queryParameters: queryParameters, options: requestOptions, cancelToken: requestCancelToken, onSendProgress: onSendProgress, onReceiveProgress: onReceiveProgress)
          : _dio.get(path, queryParameters: queryParameters, options: requestOptions, cancelToken: requestCancelToken, onReceiveProgress: onReceiveProgress),
      path: path,
      isPost: isPost,
      retryCount: retryCount,
      retryDelay: retryDelay,
    ).then((response) => response != null ? onSuccess(_processResponse(response)) : null); // 处理响应
  }

  // 执行 GET 请求，返回解析后的数据
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
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData), // 解析响应数据
    );
  }

  // 执行 GET 请求，返回完整 Response
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
      onSuccess: (response) => response, // 返回完整响应
    );
  }

  // 执行 POST 请求，返回解析后的数据
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
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData), // 解析响应数据
    );
  }

  // 执行 POST 请求，返回完整 Response
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
      onSuccess: (response) => response, // 返回完整响应
    );
  }

  // 下载文件，支持进度回调
  Future<int?> downloadFile(
    String url,
    String savePath, {
    ValueChanged<double>? progressCallback,
  }) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url); // 生成下载请求头
      DateTime? lastUpdate;
      double lastProgress = 0.0;
      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: downloadReceiveTimeoutSeconds), // 下载超时
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0 || progressCallback == null) return;
          final progress = received / total; // 计算下载进度
          final now = DateTime.now();
          if (lastUpdate == null || now.difference(lastUpdate!).inMilliseconds >= 500) {
            progressCallback(progress); // 每 500ms 更新进度
            lastUpdate = now;
            lastProgress = progress;
          }
        },
      );
      if (progressCallback != null && lastProgress < 1.0) progressCallback(1.0); // 确保进度到 100%
      if (response.statusCode != successStatusCode) {
        throw DioException(requestOptions: response.requestOptions, error: '状态码: ${response.statusCode}'); // 状态码异常
      }
      LogUtil.i('文件下载成功: $url,保存路径: $savePath'); // 下载成功日志
      return response.statusCode;
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace); // 下载失败日志
      return defaultFallbackStatusCode; // 返回默认失败状态码
    }
  }
}

// 统一处理 Dio 请求异常
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut, // 连接超时
      DioExceptionType.sendTimeout => S.current.netSendTimeout, // 发送超时
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout, // 接收超时
      DioExceptionType.badResponse => S.current.netBadResponse(e.response?.statusCode ?? ''), // 响应错误
      DioExceptionType.cancel => S.current.netCancel, // 请求取消
      _ => e.message.toString() // 其他错误
    };
    LogUtil.v(message); // 记录错误信息
  }, '处理 DioException 错误时发生异常'); // 异常处理日志
}
