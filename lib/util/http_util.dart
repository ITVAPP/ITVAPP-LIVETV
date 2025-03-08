import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:async/async.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式
  final http.Client _client = http.Client(); // HTTP 客户端

  // 默认超时时间
  static const Duration _defaultConnectTimeout = Duration(seconds: 3);
  static const Duration _defaultReceiveTimeout = Duration(seconds: 8);
  
  // 重试延迟上限，避免延迟时间过长
  static const Duration _maxRetryDelay = Duration(seconds: 30); // 重试延迟上限

  factory HttpUtil() => _instance;

  HttpUtil._() {
    // 配置 HttpClient
    HttpOverrides.global = _HttpOverrides();
  }

  // 配置底层 HttpClient
  static void configureHttpClient(HttpClient client) {
    client.maxConnectionsPerHost = 5; // 限制每个主机的最大连接数
    client.autoUncompress = true; // 自动解压 gzip、deflate、br
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      _logWarning('不受信任的证书: $host:$port');
      return true; // 接受所有证书
    };
  }

  // 统一请求方法，支持多种返回值类型
  Future<T?> request<T>({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelableOperation? cancelOperation,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    required T? Function(Response response) onSuccess,
  }) async {
    http.Response? response;
    int currentAttempt = 0;

    // 提前计算超时值，避免重复调用
    final connectTimeout = _getTimeout(options?.sendTimeout, _defaultConnectTimeout);
    final receiveTimeout = _getTimeout(options?.receiveTimeout, _defaultReceiveTimeout);
    final followRedirects = options?.followRedirects ?? true;

    while (currentAttempt < retryCount) {
      if (cancelOperation?.isCanceled ?? false) {
        _logInfo('请求已取消: $path');
        return null;
      }

      try {
        final headers = options?.headers != null && options!.headers!.isNotEmpty
            ? options.headers!
            : HeadersConfig.generateHeaders(url: path);

        final uri = Uri.parse(path).replace(queryParameters: queryParameters);

        // 根据方法执行请求
        response = await _executeRequest(
          method: method.toUpperCase(),
          uri: uri,
          headers: headers,
          data: data,
          receiveTimeout: receiveTimeout,
        );

        // 处理不跟随重定向
        if (!followRedirects && response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            return onSuccess(Response(
              data: response.body,
              statusCode: response.statusCode,
              headers: response.headers,
              requestOptions: RequestOptions(path: location),
            ));
          }
        }

        final convertedResponse = _convertHttpResponse(response);
        return onSuccess(convertedResponse);
      } catch (e, stackTrace) {
        currentAttempt++;
        _logError('第 $currentAttempt 次 $method 请求失败: $path\n错误详情: $e', e, stackTrace);

        if (currentAttempt >= retryCount || e is HttpCancelException) {
          formatError(e);
          return null;
        }

        // 使用新的重试延迟计算方法，加入上限控制
        final delay = _calculateRetryDelay(retryDelay, currentAttempt);
        await Future.delayed(delay);
        _logInfo('等待 ${delay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
  }

  // 添加计算重试延迟的工具函数，加入上限控制
  Duration _calculateRetryDelay(Duration baseDelay, int attempt) {
    final delay = baseDelay * (1 << (attempt - 1));
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  // 执行 HTTP 请求的核心逻辑
  Future<http.Response> _executeRequest({
    required String method,
    required Uri uri,
    required Map<String, dynamic> headers,
    dynamic data,
    required Duration receiveTimeout,
  }) async {
    // 提前将 headers 转换为正确的类型，避免重复转换
    final castedHeaders = headers.cast<String, String>();
    // 提取公共逻辑到 _encodeBody 函数
    final body = _encodeBody(data);
    switch (method) {
      case 'POST':
        return await _client
            .post(
              uri,
              headers: castedHeaders,
              body: body,
            )
            .timeout(receiveTimeout);
      case 'HEAD':
        return await _client
            .head(
              uri,
              headers: castedHeaders,
            )
            .timeout(receiveTimeout);
      case 'PUT':
        return await _client
            .put(
              uri,
              headers: castedHeaders,
              body: body,
            )
            .timeout(receiveTimeout);
      case 'DELETE':
        return await _client
            .delete(
              uri,
              headers: castedHeaders,
              body: body,
            )
            .timeout(receiveTimeout);
      default: // 默认 GET
        return await _client
            .get(
              uri,
              headers: castedHeaders,
            )
            .timeout(receiveTimeout);
    }
  }

  // 编码请求体的工具函数
  String? _encodeBody(dynamic data) {
    return data is String ? data : (data != null ? jsonEncode(data) : null);
  }

  // GET 请求方法
  Future<T?> get<T>({
    required String path,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelableOperation? cancelOperation,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return request<T>(
      method: options?.method ?? 'GET',
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelOperation: cancelOperation,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // POST 请求方法
  Future<T?> post<T>({
    required String path,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelableOperation? cancelOperation,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return request<T>(
      method: options?.method ?? 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelOperation: cancelOperation,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // 文件下载方法（优化版本）
  Future<int?> downloadFile({
    required String url, // 下载文件的 URL
    required String savePath, // 文件保存路径
    ValueChanged<double>? progressCallback, // 下载进度回调
    Duration timeout = const Duration(minutes: 5), // 默认超时时间为 5 分钟
    CancelableOperation? cancelOperation, // 可取消操作，用于支持手动取消下载
  }) async {
    // 用于存储流订阅，以便在需要时取消
    StreamSubscription<List<int>>? streamSubscription;
    try {
      // 生成请求头
      final headers = HeadersConfig.generateHeaders(url: url);
      // 创建流式请求
      final request = http.StreamedRequest('GET', Uri.parse(url));
      headers.forEach((key, value) => request.headers[key] = value);

      // 发送请求并获取响应流
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw HttpException('下载失败，状态码: ${response.statusCode}');
      }

      // 获取文件总大小，用于计算下载进度
      final total = response.contentLength ?? 0;
      int received = 0; // 已接收的字节数
      final sink = File(savePath).openWrite(); // 创建文件写入流

      // 监听响应流，处理下载数据
      streamSubscription = response.stream.listen(
        (chunk) {
          // 检查是否取消下载
          if (cancelOperation?.isCanceled ?? false) {
            streamSubscription?.cancel(); // 取消流订阅
            sink.close(); // 关闭文件流
            throw HttpCancelException('下载已取消');
          }
          received += chunk.length; // 更新已接收字节数
          sink.add(chunk); // 将数据写入文件
          if (total > 0) {
            progressCallback?.call(received / total); // 更新下载进度
          }
        },
        onDone: () async {
          await sink.close(); // 下载完成，关闭文件流
          _logInfo('文件下载成功: $url, 保存路径: $savePath');
        },
        onError: (e) async {
          await sink.close(); // 出错时关闭文件流
          throw e; // 抛出错误
        },
        cancelOnError: true, // 发生错误时自动取消订阅
      );

      // 等待下载完成
      await streamSubscription.asFuture();
      return response.statusCode; // 返回成功状态码
    } on TimeoutException catch (e) {
      // 处理超时异常
      _logError('文件下载超时: $url', e, null);
      await streamSubscription?.cancel(); // 取消流订阅
      return 408; // 返回 408 Request Timeout
    } on HttpCancelException catch (e) {
      // 处理取消异常
      _logInfo('文件下载已取消: $url');
      return 499; // 返回 499 Client Closed Request
    } on HttpException catch (e) {
      // 处理 HTTP 异常
      _logError('文件下载失败: $url, 错误详情: ${e.message}', e, null);
      return int.tryParse(e.message.split(': ').last) ?? 500; // 返回具体的状态码或默认 500
    } catch (e, stackTrace) {
      // 处理其他未知异常
      _logError('文件下载失败: $url', e, stackTrace);
      return 500; // 返回 500 Internal Server Error
    } finally {
      // 注意：不再关闭 _client，因为它是单例对象，应保持存活以复用连接
      await streamSubscription?.cancel(); // 确保流订阅被取消
    }
  }

  // 类型解析函数
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    if (data == null) return null;
    if (data is String) data = data.trim();

    if (parseData != null) {
      try {
        return parseData(data);
      } catch (e, stackTrace) {
        _logError('自定义解析失败: $data', e, stackTrace);
        return null;
      }
    }

    // 使用映射表优化类型转换
    final typeHandlers = {
      String: () {
        if (data is String) return data as T;
        if (data is Map || data is List) return jsonEncode(data) as T;
        if (data is int || data is double || data is bool) return data.toString() as T;
        return null;
      },
      int: () => data is int ? data as T : null,
      double: () => data is double ? data as T : null,
      bool: () => data is bool ? data as T : null,
    };

    final handler = typeHandlers[T];
    if (handler != null) {
      final result = handler();
      if (result != null) return result;
      _logError('无法将数据转换为 $T: $data (类型: ${data.runtimeType})', null, null);
      return null;
    }

    try {
      return data is T ? data as T : null;
    } catch (e) {
      _logError('类型转换失败: $data 无法转换为 $T', null, null);
      return null;
    }
  }

  // 超时设置工具函数
  Duration _getTimeout(Duration? customTimeout, Duration defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout;
  }

  // 转换 http.Response 为自定义 Response
  static Response _convertHttpResponse(http.Response response) {
    return Response(
      data: response.body,
      statusCode: response.statusCode,
      headers: response.headers,
      requestOptions: RequestOptions(path: response.request?.url.toString() ?? ''),
    );
  }

  // 统一日志管理
  static void _logInfo(String message) => LogUtil.i(message);
  static void _logWarning(String message) => LogUtil.i(message);
  static void _logError(String message, dynamic error, StackTrace? stackTrace) =>
      LogUtil.logError(message, error, stackTrace);
}

class Response {
  dynamic data;
  int? statusCode;
  Map<String, String> headers;
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

class HttpCancelException implements Exception {
  final String message;

  HttpCancelException(this.message);

  @override
  String toString() => 'HttpCancelException: $message';
}

class _HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    HttpUtil.configureHttpClient(client);
    return client;
  }
}

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
