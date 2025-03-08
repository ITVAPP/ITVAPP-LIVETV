import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart'; 
import 'package:itvapp_live_tv/generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式
  final http.Client _client = http.Client(); // http 客户端

  // 默认超时时间
  Duration connectTimeout = const Duration(seconds: 3);
  Duration receiveTimeout = const Duration(seconds: 8);

  CancelToken cancelToken = CancelToken(); // 模拟 CancelToken

  factory HttpUtil() => _instance;

  HttpUtil._() {
    // 配置 HttpClient
    HttpOverrides.global = _HttpOverrides();
  }

  // 配置底层 HttpClient
  static void configureHttpClient(HttpClient client) {
    client.maxConnectionsPerHost = 5;
    client.autoUncompress = true; // 自动解压 gzip、deflate、br
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }

  // 超时设置工具函数
  Duration _getTimeout(Duration? customTimeout, Duration? defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout ?? const Duration(seconds: 3);
  }

  // 类型解析函数
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null;

    if (data is String) data = data.trim();

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
      if (data is int || data is double || data is bool) return data.toString() as T;
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})');
      return null;
    }

    try {
      return data is T ? data as T : null;
    } catch (e) {
      LogUtil.e('类型转换失败: $data 无法转换为 $T');
      return null;
    }
  }

  static Response _convertHttpResponse(http.Response response) {
    return Response(
      data: response.body,
      statusCode: response.statusCode,
      headers: response.headers,
      requestOptions: RequestOptions(path: response.request?.url.toString() ?? ''),
    );
  }

  // 核心请求逻辑，使用 http 包
  Future<R?> _performRequest<R>({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    required R? Function(Response response) onSuccess,
  }) async {
    http.Response? response;
    int currentAttempt = 0;

    while (currentAttempt < retryCount) {
      try {
        final headers = options?.headers != null && options!.headers!.isNotEmpty
            ? options.headers!
            : HeadersConfig.generateHeaders(url: path);

        final uri = Uri.parse(path).replace(queryParameters: queryParameters);
        // 修改部分：支持 receiveTimeout 和 sendTimeout（使用 connectTimeout 替代）
        final receiveTimeoutValue = _getTimeout(options?.receiveTimeout, receiveTimeout);
        final connectTimeoutValue = _getTimeout(options?.sendTimeout, connectTimeout);

        // 修改部分：支持 followRedirects（http.Client 默认跟随重定向，需手动处理禁用）
        final followRedirects = options?.followRedirects ?? true;

        // 根据 followRedirects 和 method 处理请求
        switch (method.toUpperCase()) {
          case 'POST':
            response = await _client
                .post(
                  uri,
                  headers: headers.cast<String, String>(),
                  body: data is String ? data : jsonEncode(data),
                )
                .timeout(receiveTimeoutValue); // 只支持 receiveTimeout
            break;
          case 'HEAD':
            response = await _client
                .head(
                  uri,
                  headers: headers.cast<String, String>(),
                )
                .timeout(receiveTimeoutValue);
            break;
          default: // 默认 GET
            response = await _client
                .get(
                  uri,
                  headers: headers.cast<String, String>(),
                )
                .timeout(receiveTimeoutValue);
            break;
        }

        // 修改部分：手动处理不跟随重定向
        if (!followRedirects && response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            return onSuccess(Response(
              data: response.body,
              statusCode: response.statusCode,
              headers: response.headers,
              requestOptions: RequestOptions(path: location), // 返回重定向位置
            ));
          }
        }

        return onSuccess(_convertHttpResponse(response));
      } catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError(
          '第 $currentAttempt 次 $method 请求失败: $path\n'
          '错误详情: $e',
          e,
          stackTrace,
        );

        if (currentAttempt >= retryCount || (e is HttpCancelException)) {
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
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      method: options?.method ?? 'GET',
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
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
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      method: options?.method ?? 'GET',
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
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
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      method: options?.method ?? 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
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
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      method: options?.method ?? 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) {
        if (response.data is String) response.data = response.data.trim();
        return response;
      },
    );
  }

  // 文件下载方法（保持不变）
  Future<int?> downloadFile(
    String url,
    String savePath, {
    ValueChanged<double>? progressCallback,
  }) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      final request = http.StreamedRequest('GET', Uri.parse(url));
      headers.forEach((key, value) => request.headers[key] = value);

      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw Exception('状态码: ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final sink = File(savePath).openWrite();

      await response.stream.listen(
        (chunk) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) progressCallback?.call(received / total);
        },
        onDone: () async {
          await sink.close();
          LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
        },
        onError: (e) async {
          await sink.close();
          throw e;
        },
        cancelOnError: true,
      ).asFuture();

      return response.statusCode;
    } catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500;
    }
  }
}

// 简化的 Response 类，使用 http 的 headers
class Response {
  dynamic data;
  int? statusCode;
  Map<String, String> headers; // 直接使用 http 的 headers 类型
  RequestOptions requestOptions;

  Response({
    required this.data,
    required this.statusCode,
    required this.headers,
    required this.requestOptions,
  });
}

class Options {
  Map<String, dynamic>? headers;
  Map<String, dynamic>? extra;
  String? method;
  // 修改部分：添加 receiveTimeout、sendTimeout 和 followRedirects
  Duration? receiveTimeout;
  Duration? sendTimeout;
  bool? followRedirects;

  Options({
    this.headers,
    this.extra,
    this.method,
    this.receiveTimeout,
    this.sendTimeout,
    this.followRedirects,
  });
}

class RequestOptions {
  String path;

  RequestOptions({required this.path});
}

class CancelToken {
  bool _isCancelled = false;

  void cancel([String? reason]) {
    _isCancelled = true;
    throw HttpCancelException(reason ?? 'Request cancelled');
  }

  bool get isCancelled => _isCancelled;
}

// 自定义异常类
class HttpCancelException implements Exception {
  final String message;

  HttpCancelException(this.message);

  @override
  String toString() => 'HttpCancelException: $message';
}

// 自定义 HttpOverrides 配置 HttpClient
class _HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    HttpUtil.configureHttpClient(client);
    return client;
  }
}

// 统一处理 HTTP 请求的异常
void formatError(dynamic e) {
  LogUtil.safeExecute(() {
    final message = switch (e.runtimeType) {
      TimeoutException => S.current.netTimeOut,
      HttpCancelException => S.current.netCancel,
      _ => e.toString(),
    };
    LogUtil.v(message);
  }, '处理 HTTP 错误时发生异常');
}
