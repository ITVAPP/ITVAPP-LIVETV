import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import '../generated/l10n.dart';

// 定义 DIO 相关类以兼容接口
class HttpCancelToken {
  bool isCancelled = false;
  void cancel() => isCancelled = true;
}

class Options {
  final Map<String, String>? headers;
  final Duration? receiveTimeout;
  final Map<String, dynamic>? extra;

  Options({this.headers, this.receiveTimeout, this.extra});

  Options copyWith({
    Map<String, String>? headers,
    Duration? receiveTimeout,
    Map<String, dynamic>? extra,
  }) {
    return Options(
      headers: headers ?? this.headers,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      extra: extra ?? this.extra,
    );
  }
}

class DioException implements Exception {
  final String? message;
  final DioExceptionType type;
  final dynamic error;
  final Response? response;
  final RequestOptions requestOptions;

  DioException({
    this.message,
    required this.type,
    this.error,
    this.response,
    required this.requestOptions,
  });
}

enum DioExceptionType {
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  badResponse,
  cancel,
  other,
}

class Response<T> {
  final T? data;
  final int? statusCode;
  final RequestOptions requestOptions;

  Response({
    this.data,
    this.statusCode,
    required this.requestOptions,
  });
}

class RequestOptions {
  final String path;
  final Map<String, dynamic>? queryParameters;
  final Options? options;

  RequestOptions({
    required this.path,
    this.queryParameters,
    this.options,
  });
}

typedef ProgressCallback = void Function(int count, int total);

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  final Duration connectTimeout;
  final Duration receiveTimeout;
  late final http.Client _client;
  bool _isCancelled = false;

  // 初始化基础配置，这里主要设置超时时间，headers 在具体请求时动态生成
  HttpUtil._()
      : connectTimeout = const Duration(seconds: 3),
        receiveTimeout = const Duration(seconds: 6) {
    _client = http.Client();
    HttpOverrides.global = _CustomHttpOverrides();
    LogUtil.i('HttpUtil initialized'); // 保持日志记录
  }

  factory HttpUtil() {
    return _instance;
  }

  void cancelRequests() {
    _isCancelled = true;
    LogUtil.i('所有请求已取消');
  }

  // 辅助方法：从 Content-Type 头中提取字符集
  String? _getCharset(String? contentType) {
    if (contentType == null) return null;
    
    final regex = RegExp(r'charset=([^\s;]+)', caseSensitive: false);
    final match = regex.firstMatch(contentType);
    return match?.group(1)?.toLowerCase();
  }

  // GET 请求方法，确保返回 String? 时不会出错
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      HttpCancelToken? cancelToken,
      ProgressCallback? onReceiveProgress,
      int retryCount = 2,
      Duration retryDelay = const Duration(seconds: 2)}) async {
    Uri uri = Uri.parse(path);
    if (queryParameters != null) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    
    int currentAttempt = 0;
    Duration currentDelay = retryDelay;

    while (currentAttempt < retryCount) {
      try {
        // 检查是否需要取消请求
        if (_isCancelled || cancelToken?.isCancelled == true) {
          throw DioException(
            type: DioExceptionType.cancel,
            requestOptions: RequestOptions(path: path),
          );
        }

        LogUtil.i('发起请求: $uri'); // 请求日志
        LogUtil.i('Headers: ${HeadersConfig.generateHeaders(url: path)}'); // 请求头日志

        final response = await _client
            .get(
              uri,
              headers: {
                'Accept-Charset': 'utf-8',  // 添加字符集设置
                ...HeadersConfig.generateHeaders(url: path),
                ...?options?.headers,
              },
            )
            .timeout(options?.receiveTimeout ?? connectTimeout);

        LogUtil.i('响应状态码: ${response.statusCode}'); // 响应状态码日志

        if (response.statusCode == 200) {
          if (T == String) {
            // 如果响应头中包含字符集信息，优先使用该字符集
            final charset = _getCharset(response.headers['content-type']);
            LogUtil.i('检测到响应字符集: $charset'); // 添加字符集检测日志
            
            // 尝试使用检测到的字符集进行解码，如果失败则回退到 UTF-8
            try {
              if (charset != null && charset != 'utf-8') {
                // 如果检测到特定字符集，尝试使用该字符集解码
                final decoder = Encoding.getByName(charset) ?? utf8;
                return decoder.decode(response.bodyBytes) as T;
              }
            } catch (e) {
              LogUtil.i('使用检测到的字符集解码失败，回退到 UTF-8: $e');
            }
            
            // 默认或回退使用 UTF-8 解码
            return utf8.decode(response.bodyBytes, allowMalformed: true) as T;
          }
          // 对于非字符串类型的响应，直接返回
          return response.body as T;
        }
        
        throw DioException(
          type: DioExceptionType.badResponse,
          response: Response(
            data: response.body,
            statusCode: response.statusCode,
            requestOptions: RequestOptions(path: path),
          ),
          requestOptions: RequestOptions(path: path),
        );
      } catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace);

        if (currentAttempt >= retryCount) {
          formatError(_mapToDioException(e, path));
          return null;
        }

        await Future.delayed(currentDelay);
        currentDelay *= 2;
        LogUtil.i('等待 ${currentDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
  }

  // 文件下载方法，支持显示下载进度
  Future<int?> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      
      LogUtil.i('开始下载文件: $url'); // 下载开始日志
      
      final response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final file = File(savePath);
        final bytes = response.bodyBytes;
        final totalBytes = bytes.length;
        
        // 分块写入并更新进度
        final chunkSize = 1024 * 1024; // 1MB chunks
        var written = 0;
        
        final sink = file.openWrite();
        for (var i = 0; i < totalBytes; i += chunkSize) {
          if (_isCancelled) {
            await sink.close();
            return null;
          }
          
          final end = (i + chunkSize < totalBytes) ? i + chunkSize : totalBytes;
          sink.add(bytes.sublist(i, end));
          written += end - i;
          
          progressCallback?.call(written / totalBytes);
        }
        await sink.close();
        
        LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
        return response.statusCode;
      }

      LogUtil.logError('文件下载失败: $url', 'Status code: ${response.statusCode}', StackTrace.current);
      return 500;
    } catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500;
    }
  }

  void dispose() {
    _isCancelled = true;
    _client.close();
    LogUtil.i('HttpUtil disposed');
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..maxConnectionsPerHost = 5
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

DioException _mapToDioException(dynamic error, String path) {
  final requestOptions = RequestOptions(path: path);

  if (error is TimeoutException) {
    return DioException(
      type: DioExceptionType.connectionTimeout,
      requestOptions: requestOptions,
    );
  }

  if (error is DioException) {
    return error;
  }

  return DioException(
    type: DioExceptionType.other,
    error: error,
    requestOptions: requestOptions,
  );
}

void formatError(DioException e) {
  LogUtil.safeExecute(() {
    final message = switch (e.type) {
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
}
